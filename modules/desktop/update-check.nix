# The mark in the bar when there is a newer version of the distribution.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  branding = import ../../branding.nix;
  inherit (branding) id;
  cfg = config.${id}.desktop;

  # Asks GitHub whether the branch this machine follows has moved past the version installed, and
  # what changed: $XDG_RUNTIME_DIR/<id>/update.json, which the bar shows as a mark
  updateCheck = pkgs.writeShellApplication {
    name = "${id}-update-check";
    runtimeInputs = with pkgs; [
      git
      jq
      curl
      coreutils
    ];
    text = ''
      lock=/etc/nixos/flake.lock
      out="$XDG_RUNTIME_DIR/${id}/update.json"
      mkdir -p "''${out%/*}"
      read -r owner repo ref rev < <(jq -r '.nodes[.nodes.root.inputs["${id}"]]
        | [.original.owner, .original.repo, (.original.ref // "HEAD"), .locked.rev] | join(" ")' "$lock")
      target="refs/heads/$ref"
      [ "$ref" != HEAD ] || target=HEAD
      new=$(git ls-remote "https://github.com/$owner/$repo" "$target" 2>/dev/null | cut -f 1 || true)
      # No network: what was known stays
      [ -n "$new" ] || exit 0
      if [ "$new" = "$rev" ]; then
        echo '{"available": false}' >"$out.new"
      else
        changes=$(curl --fail --silent --max-time 15 \
          "https://api.github.com/repos/$owner/$repo/compare/$rev...$new" \
          | jq '[.commits[].commit.message | split("\n")[0]] | reverse' 2>/dev/null) || changes="[]"
        jq -n --arg rev "$new" --argjson changes "''${changes:-[]}" \
          '{available: true, rev: $rev, changes: $changes}' >"$out.new"
      fi
      mv -f "$out.new" "$out"
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = lib.optionals (!cfg.live) [ updateCheck ];

    # Looks for a newer version two minutes after the login and then every hour
    systemd.user.services."${id}-update-check" = lib.mkIf (!cfg.live) {
      description = "Look for a newer version of ${branding.name}";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe updateCheck;
      };
    };
    systemd.user.timers."${id}-update-check" = lib.mkIf (!cfg.live) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnStartupSec = "2min";
        OnUnitActiveSec = "1h";
      };
    };
  };
}
