output "db_instance_id" {
  description = "DB instance identifier."
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "Full ARN of the DB instance. Pass to a replica in the DR region as source_db_arn."
  value       = aws_db_instance.this.arn
}

output "db_resource_id" {
  description = "DBI resource ID (dbi-XXXXXXXXXXX). Use for IAM DB auth ARN construction."
  value       = aws_db_instance.this.resource_id
}

output "endpoint" {
  description = "DB endpoint in host:port form."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "DB host only (no port)."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "DB port."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Initial database name. Null on replica."
  value       = aws_db_instance.this.db_name
}

output "parameter_group_name" {
  description = "Parameter group attached to the writer. Null on replica."
  value       = one(aws_db_parameter_group.this[*].name)
}
