{ config, pkgs, ...}:
let 
in 
{
  programs.git = {
    enable = true;
    userName = "Travis Huffman";
    userEmail = "huffmantravis57@protonmail.com";
  };
}