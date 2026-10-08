# Extra data drives. setup.sh regenerates this file after finding the drives
# on the machine, so edit it by hand only if the detection got it wrong.
{ ... }:
{
  fileSystems."/mnt/GD1" = {
    device = "/dev/disk/by-uuid/f872ffaa-a901-4f8b-9135-10bb98cd6db8";
    fsType = "ext4";
    options = [ "nofail" ];
  };
  fileSystems."/mnt/GD2" = {
    device = "/dev/disk/by-uuid/f96fa08b-a212-466d-817c-1d15cf5a323f";
    fsType = "btrfs";
    options = [ "nofail" ];
  };
}
