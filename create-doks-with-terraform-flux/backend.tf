# Store the state file using DO Spaces
# DO Spaces is similar to AWS S3 so the meaning of the properties used down below is the same

terraform {
  backend "s3" {
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    endpoint                    = "https://fra1.digitaloceanspaces.com" # replace this with your Spaces endpoint
    region                      = "us-east-1"         # usually this can be left as it is
    bucket                      = "doks-fluxcd"       # replace this with your bucket name
    key                         = "terraform.tfstate" # replaces this with your full path if the state file is not in the "root folder" of your bucket
  }
}
