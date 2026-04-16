extract_manifest_urls() {
  printf '%s\n' "$settings_yaml" | awk '
    /^local-db-remotes:[[:space:]]*$/ {
      in_remotes = 1
      next
    }

    in_remotes {
      if ($0 ~ /^[^[:space:]]/) {
        exit
      }

      if ($0 ~ /^[[:space:]]+[^:#][^:]*:[[:space:]]*/) {
        value = $0
        sub(/^[[:space:]]+[^:#][^:]*:[[:space:]]*/, "", value)
        sub(/[[:space:]]+#.*$/, "", value)
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)

        if (value ~ /^".*"$/ || value ~ /^'\''.*'\''$/) {
          value = substr(value, 2, length(value) - 2)
        }

        if (length(value) > 0) {
          print value
        }
      }
    }
  '
}

resolve_publish_target() {
  manifest_urls=()

  while IFS= read -r manifest_url_candidate; do
    if [ -n "$manifest_url_candidate" ]; then
      manifest_urls+=("$manifest_url_candidate")
    fi
  done < <(extract_manifest_urls | sort -u)

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
