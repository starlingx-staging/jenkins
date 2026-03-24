#!/usr/bin/env python3
import os
import gzip
import hashlib
import argparse

REQUIRED_FILES = ["Release", "Packages", "Packages.gz"]

def calculate_checksum(path, algo="sha256"):
    """Calculate checksum of a file."""
    h = hashlib.new(algo)
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            h.update(chunk)
    return h.hexdigest()

def parse_release_file(release_path):
    """Parse Release file into dict of checksums."""
    checksums = {"sha256": {}, "md5": {}}
    with open(release_path, "r") as f:
        lines = f.readlines()

    current_algo = None
    for line in lines:
        if line.startswith("SHA256:"):
            current_algo = "sha256"
            continue
        elif line.startswith("MD5Sum:"):
            current_algo = "md5"
            continue
        elif current_algo and line.strip():
            parts = line.strip().split()
            if len(parts) == 3:
                checksum, size, filename = parts
                checksums[current_algo][filename] = (checksum, int(size))
    return checksums

def validate_packages_file(path):
    """Validate that the Packages file exists and is readable."""
    try:
        if path.endswith(".gz"):
            with gzip.open(path, "rt") as f:
                _ = f.readline()
        else:
            with open(path, "r") as f:
                _ = f.readline()
        return True
    except Exception as e:
        print(f"[ERROR] Cannot read {path}: {e}")
        return False

def validate_repo_structure(repo_path):
    """Ensure basic Debian repo structure exists."""
    dists_path = os.path.join(repo_path, "dists")
    pool_path = os.path.join(repo_path, "pool")

    if not os.path.isdir(dists_path):
        print(f"[ERROR] Missing dists/ directory at {repo_path}")
        return False

    if not os.path.isdir(pool_path):
        print(f"[WARNING] Missing pool/ directory at {repo_path}")

    return True

def validate_release_checksums(release_path, repo_path):
    """Validate checksums from Release file."""
    checksums = parse_release_file(release_path)
    all_good = True

    for algo in checksums:
        for filename, (expected_hash, _) in checksums[algo].items():
            file_path = os.path.join(os.path.dirname(release_path), filename)
            if not os.path.exists(file_path):
                print(f"[ERROR] Missing file '{filename}' referenced in Release '{release_path}'")
                all_good = False
                continue

            actual_hash = calculate_checksum(file_path, algo)
            if actual_hash != expected_hash:
                print(f"[ERROR] {filename} {algo} mismatch!")
                all_good = False

    return all_good

def should_check_path(path, dist, sections, archs):
    """
    Decide whether to validate a given path based on requested dist, sections, and architectures.
    Example paths:
        dists/bookworm/main/binary-amd64/Packages.gz
        dists/bookworm/contrib/binary-arm64/Packages.gz
    """
    # Restrict to specific dist
    if dist and f"dists/{dist}" not in path:
        return False

    # Restrict to selected sections
    if sections:
        if not any(f"/{section}/" in path for section in sections):
            return False

    # Restrict to selected architectures
    if archs:
        if not any(f"binary-{arch}" in path for arch in archs):
            return False

    return True

def validate_debian_repo(repo_path, dist=None, sections=None, archs=None):
    print(f"Validating Debian repository at: {repo_path}")
    if dist:
        print(f"[INFO] Restricting to distribution: {dist}")
    if sections:
        print(f"[INFO] Restricting to sections: {', '.join(sections)}")
    if archs:
        print(f"[INFO] Restricting to architectures: {', '.join(archs)}")

    if not validate_repo_structure(repo_path):
        return False

    dists_path = os.path.join(repo_path, "dists")
    success = True

    for root, dirs, files in os.walk(dists_path):
        # Skip irrelevant paths based on section/arch filters
        if not should_check_path(root, dist, sections, archs):
            continue

        if "Release" in files:
            release_path = os.path.join(root, "Release")
            print(f"\n[INFO] Checking Release file: {release_path}")

            if not validate_release_checksums(release_path, repo_path):
                success = False

        for required in REQUIRED_FILES:
            if required in files:
                path = os.path.join(root, required)
                if "Packages" in required:
                    if not validate_packages_file(path):
                        success = False
            else:
                # Only warn about missing Packages files, since some repos skip them
                if required.startswith("Packages"):
                    print(f"[WARNING] Missing {required} in {root}")

    if success:
        print("\nRepository is valid!")
    else:
        print("\nRepository has errors!")

    return success

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validate a Debian package repository.")
    parser.add_argument("path", help="Path to the Debian repository")
    parser.add_argument("--dist", help="Distribution codename to check (e.g., bookworm, bullseye)")
    parser.add_argument("--sections", help="Comma-separated list of sections to check (e.g., main,contrib,non-free)")
    parser.add_argument("--archs", help="Comma-separated list of architectures to check (e.g., amd64,arm64,i386)")
    args = parser.parse_args()

    if not os.path.isdir(args.path):
        print(f"[ERROR] Invalid path: {args.path}")
        exit(1)

    dist = args.dist.strip() if args.dist else None
    sections = args.sections.split(",") if args.sections else None
    archs = args.archs.split(",") if args.archs else None

    valid = validate_debian_repo(args.path, dist=dist, sections=sections, archs=archs)
    exit(0 if valid else 1)
