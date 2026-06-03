output "public_ip" {
  description = "Public IP of the server"
  value       = oci_core_instance.app.public_ip
}

output "instance_id" {
  description = "OCID of the compute instance"
  value       = oci_core_instance.app.id
}
