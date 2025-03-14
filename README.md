# SmartWireguardConfig

Smartly create a WireGuard config to route only geoblocked domains via the WireGuard VPN.

## Description

This Python script resolves a list of domains to their corresponding IP addresses and updates a WireGuard configuration file to route traffic for those IPs through the VPN. This is particularly useful for bypassing geo-blocking by routing only specific domains through the VPN.

## Installation

### Option 1: With uvx (Preferred)

1. Install Astra UV from : https://docs.astral.sh/uv/getting-started/installation/
2. `uvx --from git+https://github.com/raymondclowe/SmartWireguardConfig smartwireguard`
3. As above, but add the required parameters (see below)

### Option 2: With standard python/pip

1. Ensure you have Python 3.8 or higher installed (3.12 was used for dev).
2. Clone this repository.
3. Install the required dependencies by running:

   ```bash
   pip install -r requirements.txt
   ```

### Option 3: With uv locally

1. Git clone this repo
2. `cd` inside
3. `uv sync`
4. `uv run main.py <params as below>`

## Usage

```
usage: main.py [-h] [--class IP_CLASS] [--output OUTPUT] [--overwrite] template_file domains

Update WireGuard config with resolved IPs for domains.

positional arguments:
  template_file         Path to the base/template WireGuard config file
  domains               Either a single domain or a filename containing domains (one per       
                        line, with optional CIDR [example.com{,/24}])

options:
  -h, --help            show this help message and exit
  --class IP_CLASS      Default IP class for resolved IPs (default: 32). Use 'A', 'B', 'C',    
                        'HOST', '/32', or numeric values.
  --output OUTPUT, -o OUTPUT
                        Optional output file for the updated config
  --overwrite           Overwrite the AllowedIPs field instead of appending (default is        
                        append).
```                        

1. Prepare a template WireGuard configuration file.
2. Create a text file with the domains you want to route through the VPN, one domain per line. If you have only one domain, you can specify this on the command line instead of a filename.
3. Run the script with the following command (or using uv / uvx):

   ```bash
   python main.py <path_to_template_file> <path_to_domains_file> --class <IP_class> --output <output_file>
   ```

   Example:

   ```bash
   python main.py template.conf domains.txt --class 32 --output wg0.conf
   ```

## domains.txt

The `domains.txt` file may have this format:

```
# This is a comment - lines starting with # are ignored
example.com
another-example.com,/24
// This is also a comment - lines starting with // are ignored
one-more.com,/16
```

When a class is specified on a line it overrides that specified in the command line. Lines starting with `#` or `//` are treated as comments and will be ignored by the script.


## Running Tests

To ensure the script is working correctly, you can run the provided test script on a Windows PowerShell.:

```bash
.\test.ps1
```

This script performs several tests, including:
- Resolving a single domain.
- Resolving multiple domains from a file.
- Handling invalid domains.
- Handling invalid IP classes.
- Showing the diff between the original and updated configuration files.

All tests should pass if the script is functioning correctly.

## Contributing

Contributions are welcome! Please feel free to fork and submit a Pull Request.

## "License"

It is just code, use it.
