import argparse
import dns.resolver
import sys
import os
from urllib.parse import urlparse

# Map class names to CIDR notations
CLASS_TO_CIDR = {
    "A": "/8",
    "B": "/16",
    "C": "/24",
    "HOST": "/32",  # Synonym for /32
}

def resolve_domains(domains_with_cidr, default_ip_class):
    """
    Resolve a list of domains to their IP addresses and format them with the specified class.
    Each domain can optionally include a CIDR (e.g., "domain.com,/24").
    """
    resolved_ips = set()
    for domain_with_cidr in domains_with_cidr:
        # Split domain and optional CIDR
        parts = domain_with_cidr.split(',')
        domain = parts[0].strip()
        ip_class = parts[1].strip() if len(parts) > 1 else default_ip_class

        try:
            answers = dns.resolver.resolve(domain, 'A')
            for answer in answers:
                resolved_ips.add(f"{answer}{ip_class}")
        except Exception as e:
            print(f"Failed to resolve domain {domain}: {e}", file=sys.stderr)
    return resolved_ips

def extract_domain(url_or_domain):
    """
    Extract the domain from a URL or return the input if it's already a domain.
    """
    parsed = urlparse(url_or_domain)
    return parsed.netloc if parsed.netloc else url_or_domain

def read_domains_from_file(filename):
    """
    Read domains from a file, extract domains from URLs, and return a list of domains.
    Each line can optionally include a CIDR (e.g., "domain.com,/24").
    Lines starting with '#' or '//' are treated as comments and skipped.
    """
    domains = []
    try:
        with open(filename, 'r') as f:
            for line in f:
                # Strip whitespace and extract domain (with optional CIDR)
                stripped_line = line.strip()
                # Skip empty lines and comment lines
                if stripped_line and not stripped_line.startswith('#') and not stripped_line.startswith('//'):
                    domains.append(stripped_line)
    except Exception as e:
        print(f"Error reading file {filename}: {e}", file=sys.stderr)
        sys.exit(1)
    return domains

def normalize_ip_class(ip_class):
    """
    Normalize the IP class input to a valid CIDR notation.
    Supports:
    - Numeric values (e.g., "32")
    - CIDR-style values (e.g., "/32")
    - Class names ("A", "B", "C", "HOST")
    """
    ip_class = str(ip_class).upper()  # Convert to uppercase for case-insensitivity
    if ip_class.startswith("/"):
        # Already in CIDR format
        cidr = ip_class
    elif ip_class.isdigit():
        # Numeric value, prepend "/"
        cidr = f"/{ip_class}"
    elif ip_class in CLASS_TO_CIDR:
        # Map class name to CIDR notation
        cidr = CLASS_TO_CIDR[ip_class]
    else:
        print(f"Invalid IP class: {ip_class}. Use 'A', 'B', 'C', 'HOST', '/32', or numeric values.", file=sys.stderr)
        sys.exit(1)

    # Validate the CIDR notation
    try:
        cidr_number = int(cidr[1:])  # Extract the number after "/"
        if not (0 <= cidr_number <= 32):
            raise ValueError
    except ValueError:
        print(f"Invalid CIDR notation: {cidr}. Must be between /0 and /32.", file=sys.stderr)
        sys.exit(1)

    return cidr

def update_config(template_file, allowed_ips, output_file=None, overwrite=False):
    """
    Update the AllowedIPs field in the WireGuard config file and output the result.
    If overwrite is True, replace the AllowedIPs field entirely.
    If overwrite is False, append the resolved IPs to the existing AllowedIPs field.
    
    In WireGuard, multiple AllowedIPs lines are concatenated by the client.
    """
    # Read the template file line by line
    try:
        with open(template_file, 'r') as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Error reading template file {template_file}: {e}", file=sys.stderr)
        sys.exit(1)

    # Process based on mode
    if overwrite:
        # In overwrite mode, we'll replace all AllowedIPs lines with one new line
        # Find the position of the first AllowedIPs line to replace it
        allowed_ips_index = None
        output_lines = []
        for i, line in enumerate(lines):
            if line.strip().startswith('AllowedIPs ='):
                if allowed_ips_index is None:  # Keep track of the first occurrence
                    allowed_ips_index = len(output_lines)
            else:
                output_lines.append(line)
                
        # Format the IPs string
        ip_str = ', '.join(sorted(allowed_ips))
        
        # Insert the new AllowedIPs line at the original position
        if allowed_ips_index is not None:
            output_lines.insert(allowed_ips_index, f'AllowedIPs = {ip_str}\n')
        else:
            # If no AllowedIPs line was found, add it after the [Peer] section
            peer_index = None
            for i, line in enumerate(output_lines):
                if line.strip() == '[Peer]':
                    peer_index = i
                    break
                    
            if peer_index is not None:
                output_lines.insert(peer_index + 1, f'AllowedIPs = {ip_str}\n')
            else:
                print("Error: No [Peer] section found in template", file=sys.stderr)
                sys.exit(1)
    else:
        # In append mode, we keep all existing lines (including AllowedIPs lines)
        # and add a new AllowedIPs line after the peer section
        output_lines = lines.copy()
        
        # Format the IPs string
        ip_str = ', '.join(sorted(allowed_ips))
        
        # Find the [Peer] section
        peer_index = None
        for i, line in enumerate(output_lines):
            if line.strip() == '[Peer]':
                peer_index = i
                break
        
        # If we found a [Peer] section, add the new line after it
        if peer_index is not None:
            # Add the new line after the last entry in the [Peer] section
            # but before any new section starts
            next_section_index = len(output_lines)
            for i in range(peer_index + 1, len(output_lines)):
                if output_lines[i].strip().startswith('['):
                    next_section_index = i
                    break
            
            # Insert the new AllowedIPs line right before the next section starts
            # (or at the end if there's no next section)
            output_lines.insert(next_section_index, f'AllowedIPs = {ip_str}\n')
        else:
            print("Error: No [Peer] section found in template", file=sys.stderr)
            sys.exit(1)

    # Join the lines back to a single string
    updated_content = ''.join(output_lines)

    # Output the updated config
    if output_file:
        try:
            with open(output_file, 'w') as f:
                f.write(updated_content)
            print(f"Updated configuration written to {output_file}")
        except Exception as e:
            print(f"Error writing to output file {output_file}: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        print(updated_content)

def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description="Update WireGuard config with resolved IPs for domains.")
    parser.add_argument("template_file", help="Path to the base/template WireGuard config file")
    parser.add_argument("domains", help="Either a single domain or a filename containing domains (one per line, with optional CIDR [example.com{,/24}])")
    parser.add_argument("--class", default="32", dest="ip_class", 
                        help="Default IP class for resolved IPs (default: 32). Use 'A', 'B', 'C', 'HOST', '/32', or numeric values.")
    parser.add_argument("--output", "-o", help="Optional output file for the updated config")
    parser.add_argument("--overwrite", action="store_true", 
                        help="Overwrite the AllowedIPs field instead of appending (default is append).")
    args = parser.parse_args()

    # Normalize the default IP class
    default_ip_class = normalize_ip_class(args.ip_class)

    # Determine if the domains argument is a file or a single domain
    if os.path.isfile(args.domains):
        # It's a file; read domains from it
        domains_with_cidr = read_domains_from_file(args.domains)
    else:
        # Treat it as a single domain (with optional CIDR)
        domains_with_cidr = [args.domains]

    # Resolve domains to IPs
    resolved_ips = resolve_domains(domains_with_cidr, default_ip_class)

    if not resolved_ips:
        print("No IPs resolved. Exiting.", file=sys.stderr)
        sys.exit(1)

    # Update and output the config
    update_config(args.template_file, resolved_ips, args.output, args.overwrite)

if __name__ == "__main__":
    main()
