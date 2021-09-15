# Store the state file using a DO Spaces bucket

# terraform {
#   backend "s3" {
#     skip_credentials_validation = true
#     skip_metadata_api_check     = true
#     endpoint                    = "<DO_SPACES_ENDPOINT>"  # replace this with your DO Spaces endpoint
#     region                      = "<DO_SPACES_REGION>"    # leave this as is
#     bucket                      = "<DO_SPACES_BUCKET>"    # replace this with your bucket name
#     key                         = "<TF_STATE_FILE>"       # replaces this with your state file name (e.g. terraform.tfstate)
#   }
# }
