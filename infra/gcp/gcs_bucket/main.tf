resource "random_id" "bucket_prefix" {
  byte_length = 5
}

resource "google_storage_bucket" "bucket" {
  name = "${var.short_name}-${random_id.bucket_prefix.hex}"
  location = var.location
  force_destroy = true
  storage_class = var.storage_class
  uniform_bucket_level_access = true
}
