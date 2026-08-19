variable "name" {
  description = "Short name for the bucket. A random suffix is appended for global uniqueness."
  type        = string
}

variable "environment" {
  description = "Environment this bucket belongs to."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "data_classification" {
  description = "Sensitivity of data stored. Drives inventory and handling requirements."
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["public", "internal", "confidential"], var.data_classification)
    error_message = "data_classification must be one of: public, internal, confidential."
  }
}

variable "force_destroy" {
  description = "Allow destroy to empty the bucket first. Lab convenience; false in production."
  type        = bool
  default     = false
}
