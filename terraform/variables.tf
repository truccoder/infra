variable "tenancy_ocid" {
  description = "OCI Tenancy OCID"
  type        = string
}

variable "user_ocid" {
  description = "OCI User OCID"
  type        = string
}

variable "fingerprint" {
  description = "OCI API key fingerprint"
  type        = string
}

variable "private_key_path" {
  description = "Path to OCI API private key file"
  type        = string
}

variable "region" {
  description = "OCI region (e.g. ap-singapore-1)"
  type        = string
}

variable "compartment_ocid" {
  description = "OCI Compartment OCID (defaults to tenancy root)"
  type        = string
  default     = ""
}

locals {
  compartment_ocid = var.compartment_ocid != "" ? var.compartment_ocid : var.tenancy_ocid
}

variable "ssh_public_key" {
  description = "SSH public key content for VM access"
  type        = string
}

variable "instance_shape" {
  description = "VM shape"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "Number of OCPUs (max 4 for Always Free)"
  type        = number
  default     = 2
}

variable "instance_memory_gb" {
  description = "Memory in GB (max 24 for Always Free)"
  type        = number
  default     = 12
}

variable "boot_volume_gb" {
  description = "Boot volume size in GB"
  type        = number
  default     = 100
}

variable "availability_domain_index" {
  description = "Index of availability domain to use (try 0, 1, 2 if out of capacity)"
  type        = number
  default     = 0
}
