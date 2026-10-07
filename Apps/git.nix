{ config, pkgs, ...}:
let 
in 
{
  programs.git = {
    enable = true;
    settings.user = {
      name = "Travis Huffman";
      email = "huffmantravis57@protonmail.com";
    };
  };
}