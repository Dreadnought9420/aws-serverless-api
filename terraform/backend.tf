terraform {
  # Partial backend configuration. Bucket, key and region come from
  # backend.hcl (local) or from -backend-config flags (CI), so the same code
  # can point at a different state location without being edited.
  #
  #   terraform init -backend-config=backend.hcl
  #
  # use_lockfile writes a <key>.tflock object next to the state file. It
  # replaces the DynamoDB lock table entirely; the DynamoDB arguments are
  # deprecated and slated for removal.
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}
