# Standard tag contract: lifetime, owner, project, created.
# This group holds a machine that bills by the hour, so lifetime is 1d.
# The nightly sweep deletes only Azure groups with that tag.
# created is a timestamp, so each resource ignores later changes to it.

locals {
  created = formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", timestamp())

  tags = merge(var.tags, {
    lifetime = "1d"
    created  = local.created
  })
}
