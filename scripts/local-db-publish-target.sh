extract_manifest_urls() {
  printf '%s\n' "$settings_yaml" | perl -ne '
    if (/^local-db-remotes:\s*$/) {
      $in_remotes = 1;
      next;
    }

    if ($in_remotes) {
      if (/^\S/) {
        exit;
      }

      if (/^\s+[^:#][^:]*:\s*(.+?)\s*$/) {
        my $value = $1;
        $value =~ s/\s+#.*$//;
        $value =~ s/^["\x27]//;
        $value =~ s/["\x27]$//;
        print "$value\n" if length $value;
      }
    }
  '
}

resolve_publish_target() {
  mapfile -t manifest_urls < <(extract_manifest_urls | sort -u)

  if [ "${#manifest_urls[@]}" -ne 1 ]; then
    echo "Expected exactly one unique local-db remote manifest URL, found ${#manifest_urls[@]}" >&2
    printf '  %s\n' "${manifest_urls[@]}" >&2
    exit 1
  fi

  manifest_url="${manifest_urls[0]}"
  manifest_dir_url="${manifest_url%/*}"

  if [ "$manifest_dir_url" = "$manifest_url" ]; then
    echo "Manifest URL does not contain a publish directory: $manifest_url" >&2
    exit 1
  fi
}

url_host() {
  printf '%s\n' "$1" | sed -E 's#^https?://([^/]+).*$#\1#'
}

url_path() {
  printf '%s\n' "$1" | sed -E 's#^https?://[^/]+(/.*)?$#\1#'
}

object_key_from_url() {
  local url="$1"
  local host path endpoint_host

  host="$(url_host "$url")"
  path="$(url_path "$url")"
  endpoint_host="$(url_host "$SPACES_ENDPOINT")"

  case "$host" in
    "$SPACES_BUCKET.$endpoint_host")
      printf '%s\n' "${path#/}"
      ;;
    "$endpoint_host")
      case "$path" in
        "/$SPACES_BUCKET/"*)
          printf '%s\n' "${path#/$SPACES_BUCKET/}"
          ;;
        *)
          echo "Manifest URL path is not inside bucket $SPACES_BUCKET: $url" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "Manifest URL host does not match bucket endpoint: $url" >&2
      exit 1
      ;;
  esac
}
