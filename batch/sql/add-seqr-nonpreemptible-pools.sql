-- Adds dedicated pools for the seqr loading pipeline, with the 'seqr' pool label, but non-preemptible versions 
-- run after add-seqr-pools.sql and add-nonpreemptible-pools.sql

INSERT INTO inst_colls (`name`, `is_pool`, `boot_disk_size_gb`, `max_instances`, `max_live_instances`, `cloud`)
SELECT 'seqr-standard-np', 1, boot_disk_size_gb, max_instances, max_live_instances, cloud
FROM inst_colls
WHERE name = 'standard';

INSERT INTO inst_colls (`name`, `is_pool`, `boot_disk_size_gb`, `max_instances`, `max_live_instances`, `cloud`)
SELECT 'seqr-highmem-np', 1, boot_disk_size_gb, max_instances, max_live_instances, cloud
FROM inst_colls
WHERE name = 'highmem';

INSERT INTO inst_colls (`name`, `is_pool`, `boot_disk_size_gb`, `max_instances`, `max_live_instances`, `cloud`)
SELECT 'seqr-highcpu-np', 1, boot_disk_size_gb, max_instances, max_live_instances, cloud
FROM inst_colls
WHERE name = 'highcpu';

INSERT INTO pools (`name`, `worker_type`, `worker_cores`, `worker_local_ssd_data_disk`,
  `worker_external_ssd_data_disk_size_gb`, `enable_standing_worker`, `standing_worker_cores`,
  `preemptible`, `label`)
SELECT 'seqr-standard-np', worker_type, worker_cores, worker_local_ssd_data_disk,
  worker_external_ssd_data_disk_size_gb, FALSE, standing_worker_cores,
  FALSE, 'seqr'
FROM pools
WHERE name = 'standard';

INSERT INTO pools (`name`, `worker_type`, `worker_cores`, `worker_local_ssd_data_disk`,
  `worker_external_ssd_data_disk_size_gb`, `enable_standing_worker`, `standing_worker_cores`,
  `preemptible`, `label`)
SELECT 'seqr-highmem-np', worker_type, worker_cores, worker_local_ssd_data_disk,
  worker_external_ssd_data_disk_size_gb, FALSE, standing_worker_cores,
  FALSE, 'seqr'
FROM pools
WHERE name = 'highmem';

INSERT INTO pools (`name`, `worker_type`, `worker_cores`, `worker_local_ssd_data_disk`,
  `worker_external_ssd_data_disk_size_gb`, `enable_standing_worker`, `standing_worker_cores`,
  `preemptible`, `label`)
SELECT 'seqr-highcpu-np', worker_type, worker_cores, worker_local_ssd_data_disk,
  worker_external_ssd_data_disk_size_gb, FALSE, standing_worker_cores,
  FALSE, 'seqr'
FROM pools
WHERE name = 'highcpu';