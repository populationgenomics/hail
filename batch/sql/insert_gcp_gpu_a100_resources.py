import asyncio

from gear import Database
from hailtop.utils import (
    rate_instance_hour_to_fraction_msec,
)


async def main():
    # https://cloud.google.com/compute/all-pricing#gpus
    rates = [
        ('gpu/a100-nonpreemptible/1', rate_instance_hour_to_fraction_msec(2.934, 1)),
        ('gpu/a100-preemptible/1', rate_instance_hour_to_fraction_msec(0.88, 1))
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
