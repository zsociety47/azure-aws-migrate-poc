# Standard tag contract: lifetime, owner, project, created.
# Both groups hold machines that bill by the hour, so lifetime is 1d.
# The nightly sweep deletes only Azure groups with that tag.
# created is a timestamp, so each resource ignores later changes to it.
# Otherwise every plan would try to rewrite the tag.

locals {
  created = formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", timestamp())

  tags = merge(var.tags, {
    lifetime = "1d"
    created  = local.created
  })
}
