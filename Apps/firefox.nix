{ config, pkgs, ...}:
let 
in 
{
  programs.firefox = {
    enable = false;
    profiles = {
      default = {
        id = 0;
        isDefault = true;
        settings = {
          "sidebar.verticalTabs" = true;
          "browser.ml.chat.enabled" = false;
          "sidebar.main.tools" = "";
          "browser.tabs.tabmanager.enabled" = false;  # This hides the "List All Tabs" button
          "browser.uiCustomization.state" = ''
            {
              "placements": {
                "nav-bar": [
                  "search-container",
                  "urlbar-container",
                ]
              },
            }
          '';
        };
      };
    };
  };
}