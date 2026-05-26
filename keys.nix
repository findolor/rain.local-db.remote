rec {
  keys = {
    github_do =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIMYFMrh1LLoYCZhir9LA8FpbwKOpWrZ3gpZ5VvFT5Bu github_do";
    arda =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAyTREGZCOzMsl7N9dp1saN/t7DCs7YesusVUKApMJ78";
  };

  roles = with keys; {
    infra = [ github_do arda ];
    ssh = [ github_do arda ];
  };
}
