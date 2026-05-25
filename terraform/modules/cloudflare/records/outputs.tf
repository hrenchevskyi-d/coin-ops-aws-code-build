output "record_ids" {
  value = { for key, record in cloudflare_record.this : key => record.id }
}
