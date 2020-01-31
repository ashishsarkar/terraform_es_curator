output "file" {
  value = "${local_file.IndexDeletionCurtator.filename}"
}

output "path" {
  value = "${data.archive_file.IndexDeletionCurtator-archive.output_path}"
}
