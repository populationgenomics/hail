#!/usr/bin/env python3
from typing import List, Tuple, Set
from hailtop.aiotools import BackgroundTaskManager
from contextlib import closing
from hailtop.utils import check_shell, CalledProcessError
from hailtop.utils import retry_transient_errors
from hailtop.hail_logging import configure_logging
from fswatch import Monitor, libfswatch
from threading import Thread
import os
import argparse
import asyncio
import kubernetes_asyncio as kube
import logging
import sys
import signal


configure_logging()
log = logging.getLogger('sync.py')
RSYNC_ARGS = "-av --progress --stats --exclude='*.log' --exclude='.mypy_cache' --exclude='__pycache__' --exclude='*~'"


DEVBIN = os.path.abspath(os.path.dirname(__file__))


class Sync:
    def __init__(self, paths: List[Tuple[str, str]]):
        self.pods_list: Set[Tuple[str, str]] = set()
        self.paths = paths

    async def sync_and_restart_pod(self, pod, namespace):
        try:
            await asyncio.gather(*[
                check_shell(f'{DEVBIN}/krsync.sh {RSYNC_ARGS} {local} {pod}@{namespace}:{remote}')
                for local, remote in self.paths])
            await check_shell(f'kubectl exec {pod} --namespace {namespace} -- kill -2 1')
        except CalledProcessError:
            log.warning(f'could not synchronize {namespace}/{pod}, removing from active pods', exc_info=True)
            self.pods_list.remove((pod, namespace))
            return
        log.info(f'reloaded {pod}@{namespace}')

    async def initialize_pod(self, pod, namespace):
        try:
            await asyncio.gather(*[
                check_shell(f'{DEVBIN}/krsync.sh {RSYNC_ARGS} {local} {pod}@{namespace}:{remote}')
                for local, remote in self.paths])
            await check_shell(f'kubectl exec {pod} --namespace {namespace} -- kill -2 1')
        except CalledProcessError:
            log.warning(f'could not initialize {namespace}/{pod}', exc_info=True)
            return
        self.pods_list.append((pod, namespace))
        log.info(f'initialized {pod}@{namespace}')

    async def monitor_pods(self, apps, namespace):
        await kube.config.load_kube_config()
        k8s = kube.client.CoreV1Api()
        while True:
            log.info('monitor_pods: start loop')
            updated_pods = await retry_transient_errors(
                k8s.list_namespaced_pod,
                namespace,
                label_selector=f'app in ({",".join(apps)})')
            updated_pods = {(pod.metadata.name, namespace) for pod in updated_pods.items}
            fresh_pods = updated_pods - self.pods_list
            dead_pods = self.pods_list - updated_pods
            log.info(f'monitor_pods: fresh_pods: {fresh_pods}')
            log.info(f'monitor_pods: dead_pods: {dead_pods}')
            self.pods_list = self.pods_list - dead_pods
            await asyncio.gather(*[
                self.initialize_pod(name, namespace)
                for name, namespace in fresh_pods])
            await asyncio.sleep(5)

    async def should_sync(self):
        await asyncio.gather(*[
            self.sync_and_restart_pod(pod, namespace)
            for pod, namespace in self.pods_list])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        prog='sync.py',
        description='Develop locally, deploy cloudly.',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument(
        '--app',
        action='append',
        type=str,
        help='An app label to watch.')
    parser.add_argument(
        '--namespace',
        required=False,
        type=str,
        help='The namespace in which to watch.')
    parser.add_argument(
        '--path',
        action='append',
        nargs='+',
        metavar=('local', 'remote'),
        help='The local path will be kept in sync with the remote path.')

    args = parser.parse_args(sys.argv[1:])

    with closing(asyncio.get_event_loop()) as loop:
        monitor = Monitor()
        task_manager = BackgroundTaskManager()
        try:
            sync = Sync(args.path)

            for local, _ in args.path:
                monitor.add_path(local)

            def callback(path, evt_time, flags, flags_num, event_num):
                task_manager.ensure_future_threadsafe(sync.should_sync())

            monitor.set_callback(callback)

            signal.signal(signal.SIGINT, monitor._handle_signal)
            thread = Thread(target=libfswatch.fsw_start_monitor,
                            args=(monitor.handle,),
                            daemon=True)
            thread.start()
            loop.run_until_complete(sync.monitor_pods(args.app, args.namespace))
        finally:
            try:
                task_manager.shutdown()
            finally:
                thread.join()
