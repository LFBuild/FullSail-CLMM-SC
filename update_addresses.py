import toml
import os
from pathlib import Path
import re

# --- Configuration ---
# Assume the script is run from the workspace root
WORKSPACE_ROOT = Path(".")
BUILD_ALL_SCRIPT = WORKSPACE_ROOT / "build_all.sh"

# --- Functions ---

def get_package_dirs_from_script(script_path: Path) -> list[str]:
    """Parses the build_all.sh script to find package directories."""
    package_dirs = []
    if not script_path.exists():
        print(f"Error: Build script not found at {script_path}")
        return []
    try:
        with open(script_path, 'r') as f:
            content = f.read()
            # Find directories based on 'cd ./<dir_name>' pattern
            found_dirs = re.findall(r"cd\s+\./([^ ]+)\s+&&", content)
            # Deduplicate and maintain order (though order doesn't strictly matter here)
            seen = set()
            for d in found_dirs:
                if d not in seen:
                    package_dirs.append(d)
                    seen.add(d)
    except Exception as e:
        print(f"Error reading or parsing {script_path}: {e}")
    return package_dirs

def update_toml_address(pkg_dir_name: str):
    """Updates the Move.toml address for a single package."""
    pkg_path = WORKSPACE_ROOT / pkg_dir_name
    lock_file_path = pkg_path / "Move.lock"
    toml_file_path = pkg_path / "Move.toml"

    print(f"Processing package: {pkg_dir_name}")

    if not lock_file_path.exists():
        print(f"  Skipping: {lock_file_path} not found.")
        return

    if not toml_file_path.exists():
        print(f"  Skipping: {toml_file_path} not found.")
        return

    # --- Read Move.lock ---
    published_id = None
    try:
        lock_data = toml.load(lock_file_path)
        published_id = lock_data.get("env", {}).get("mainnet", {}).get("original-published-id")
        if not published_id:
            print(f"  Skipping: 'env.mainnet.original-published-id' not found or empty in {lock_file_path}.")
            return
        print(f"  Found original-published-id: {published_id}")
    except toml.TomlDecodeError as e:
        print(f"  Error parsing {lock_file_path}: {e}")
        return
    except Exception as e:
        print(f"  Error reading {lock_file_path}: {e}")
        return

    # --- Read and Update Move.toml ---
    try:
        # Read with preserved formatting if possible (toml library doesn't guarantee this perfectly)
        with open(toml_file_path, 'r') as f:
            toml_content_str = f.read()
        toml_data = toml.loads(toml_content_str) # Use loads to parse string

        package_name = toml_data.get("package", {}).get("name")
        if not package_name:
            print(f"  Skipping: 'package.name' not found in {toml_file_path}.")
            return
        print(f"  Found package name: {package_name}")

        # Ensure 'addresses' section exists and is a dictionary
        if "addresses" not in toml_data:
            print(f"  Adding [addresses] section to {toml_file_path}")
            toml_data["addresses"] = {}
        elif not isinstance(toml_data["addresses"], dict):
             print(f"  Warning: Existing 'addresses' section in {toml_file_path} is not a table. Overwriting.")
             toml_data["addresses"] = {}


        # Update the address
        current_address = toml_data["addresses"].get(package_name)
        if current_address == published_id:
             print(f"  Address for '{package_name}' in {toml_file_path} is already up-to-date.")
             return # No need to write if unchanged

        print(f"  Updating address for '{package_name}' from '{current_address}' to '{published_id}' in {toml_file_path}")
        toml_data["addresses"][package_name] = published_id

        # Write back to Move.toml preserving as much formatting as possible
        with open(toml_file_path, "w") as f:
            toml.dump(toml_data, f)

        print(f"  Successfully updated {toml_file_path}")

    except toml.TomlDecodeError as e:
        print(f"  Error parsing {toml_file_path}: {e}")
        return
    except Exception as e:
        print(f"  Error processing {toml_file_path}: {e}")
        return

# --- Main Execution ---
if __name__ == "__main__":
    package_dirs = get_package_dirs_from_script(BUILD_ALL_SCRIPT)

    if not package_dirs:
        print("No package directories found in build script. Exiting.")
    else:
        print(f"Found package directories: {', '.join(package_dirs)}")
        print("-" * 20)
        for pkg_dir in package_dirs:
            update_toml_address(pkg_dir)
            print("-" * 20) # Separator between packages

    print("Script finished.") 