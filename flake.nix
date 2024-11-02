{
  description = "A flake providing category metadata functionality";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (pkgs) lib;

        # Predefined category groups
        categoriesList = {
          development = "Development";
          system = "System Tools";
          networking = "Networking";
          security = "Security";
          multimedia = "Multimedia";
          graphics = "Graphics";
          games = "Games";
          office = "Office";
          science = "Science";
        };

        # Function to validate categories exist
        validateCategories = categories:
          let
            invalidCategories = lib.filter (c: !(categoriesList ? ${c})) categories;
          in
            if invalidCategories != [] then
              throw "Invalid categories: ${lib.concatStringsSep ", " invalidCategories}"
            else categories;

        # Function to add single category
        addCategory = category: package:
          package.overrideAttrs (oldAttrs: {
            meta = (oldAttrs.meta or {}) // {
              categories = validateCategories [ category ];
            };
          });

        # Function to add multiple categories
        addCategories = categories: package:
          package.overrideAttrs (oldAttrs: {
            meta = (oldAttrs.meta or {}) // {
              categories = validateCategories categories;
            };
          });

        # Create JSON with both categories and package info
        flakeInfoJson = lib.generators.toJSON {} {
          categories = categoriesList;
          packages = lib.mapAttrs (name: pkg: 
            if pkg ? meta.categories
            then {
              name = name;
              categories = pkg.meta.categories;
              categoryNames = map (c: categoriesList.${c}) pkg.meta.categories;
            }
            else {
              name = name;
              categories = [];
              categoryNames = [];
            }
          ) self.packages.${system};
        };

        # Create a categories file that the script will read
        flakeInfoFile = pkgs.writeText "flake-info.json" flakeInfoJson;

        # Create a script to display categories and package info
        categories-cli = pkgs.writeShellScriptBin "categories" ''
          #!${pkgs.bash}/bin/bash

          FLAKE_INFO="${flakeInfoFile}"

          # Function to output everything as JSON
          output_json() {
            cat "$FLAKE_INFO"
          }

          # Function to display available categories
          display_categories() {
            echo "Available categories:"
            ${pkgs.jq}/bin/jq -r '.categories | to_entries | .[] | "- \(.key): \(.value)"' "$FLAKE_INFO"
          }

          # Function to list packages and their categories
          list_packages() {
            echo "Packages and their categories:"
            ${pkgs.jq}/bin/jq -r '.packages | to_entries[] | 
              select(.value.categories != []) |
              "\(.value.name):\n  Categories: \(.value.categoryNames | join(", "))"
            ' "$FLAKE_INFO"
          }

          # Function to display package info
          show_package() {
            local package="$1"
            echo "Package information for: $package"
            ${pkgs.jq}/bin/jq -r --arg pkg "$package" '
              .packages[$pkg] | 
              if . == null then
                "Package not found"
              else
                "Categories: \(.categoryNames | join(", "))"
              end
            ' "$FLAKE_INFO"
          }

          case "$1" in
            --json|-j)
              output_json
              ;;
            --packages|-p)
              list_packages
              ;;
            --package|-P)
              if [ -z "$2" ]; then
                echo "Error: Package name required"
                echo "Usage: categories --package PACKAGE_NAME"
                exit 1
              fi
              show_package "$2"
              ;;
            --help|-h)
              echo "Usage: categories [OPTIONS]"
              echo "Options:"
              echo "  --json, -j              Output all data as JSON"
              echo "  --packages, -p          List all packages and their categories"
              echo "  --package, -P NAME      Show categories for specific package"
              echo "  --help, -h              Show this help message"
              echo "  (no options)            Show available categories"
              ;;
            *)
              display_categories
              ;;
          esac
        '';

        # Library of category-related functions
        categoryLib = {
          inherit addCategory addCategories categoriesList;
          
          # Helper to check if package has specific category
          hasCategory = category: package:
            package ? meta.categories && lib.elem category package.meta.categories;

          # Helper to get all categories of a package
          getCategories = package:
            if package ? meta.categories
            then package.meta.categories
            else [];

          # Helper to get human-readable category names
          getCategoryNames = package:
            let
              cats = if package ? meta.categories
                     then package.meta.categories
                     else [];
            in
              map (c: categoriesList.${c}) cats;
        };

      in
      {
        lib = categoryLib;

        # Examples of usage within the flake itself
        packages = {
          # Single category example
          example1 = addCategory "development" pkgs.hello;
          
          # Multiple categories example
          example2 = addCategories [ "development" "system" ] pkgs.hello;
          
          default = categories-cli;
        };

        apps = {
          default = flake-utils.lib.mkApp {
            drv = categories-cli;
          };
        };
      }
    );
}