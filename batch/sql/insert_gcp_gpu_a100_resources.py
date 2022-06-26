import asyncio

from gear import Database
from hailtop.utils import (
    rate_cpu_hour_to_mcpu_msec,
    rate_gib_hour_to_mib_msec,
    rate_instance_hour_to_fraction_msec,
)


async def main():
    rates = [
        # https://cloud.google.com/compute/vm-instance-pricing#accelerator-optimized
        ('compute/a2-nonpreemptible/1', rate_cpu_hour_to_mcpu_msec(0.031611)),
        ('compute/a2-preemptible/1', rate_cpu_hour_to_mcpu_msec(0.0094833)),
        ('memory/a2-nonpreemptible/1', rate_gib_hour_to_mib_msec(0.004237)),
        ('memory/a2-preemptible/1', rate_gib_hour_to_mib_msec(0.0012711)),
        # https://cloud.google.com/compute/all-pricing#gpus
        ('gpu/a100-nonpreemptible/1', rate_instance_hour_to_fraction_msec(2.934, 1)),
        ('gpu/a100-preemptible/1', rate_instance_hour_to_fraction_msec(0.88, 1)),
    ]

    db = Database()
    await db.async_init()

    await db.execute_many('''
INSERT INTO `resources` (resource, rate)
VALUES (%s, %s)
''',
                          rates)


loop = asyncio.get_event_loop()
loop.run_until_complete(main())
