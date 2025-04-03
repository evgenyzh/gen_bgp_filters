# gen_bgp_filters

`gen_bgp_filters` is a shell script designed to generate BGP filters for different vendors, including Cisco, Juniper, and Huawei. It checks for the presence of required tools (`bgpq4` and `ipcalc`), parses user input, and generates vendor-specific BGP filter configurations.

## Usage

The script supports various options for generating BGP filters. Below is the usage legend:

```
Usage:
    -d Print debug output
    -R for allow more specific routes up to masklen
    -i for interactive input OR:
        -V C|J|H - Vendor specific: C- Cisco (default), J - Juniper, H - Huawei        
        -A ASNAME - peer or client AS-SET or AS
        -S number - peer AUTONOMOUS SYSTEM number
        -F name - as-path list number|name 
        -P name - prefix list name
        -U name - URPF standard acl number|name
        -G name - Extended in ACL number|name on interface
        -L network - Link network x.x.x.x/y

Example: gen_bgp_filters.sh -R 24 -V C -A AS-DSIJSC -S 8345 -F 11 -P prefix-dsi-in -U 1800 -G acl-dsi-in -L 10.10.10.10/30
```

## Options

- `-d`: Print debug output.
- `-R`: Allow more specific routes up to `masklen`.
- `-i`: Interactive input mode.
- `-V`: Vendor specific: `C` for Cisco (default), `J` for Juniper, `H` for Huawei.
- `-A`: AS name - peer or client AS-SET or AS.
- `-S`: Peer AUTONOMOUS SYSTEM number.
- `-F`: AS-path list number or name.
- `-P`: Prefix list name.
- `-U`: URPF standard ACL number or name.
- `-G`: Extended input ACL number or name on interface.
- `-L`: Link network in `x.x.x.x/y` format.

## Example

The following example shows how to generate a BGP filter for Cisco:

```sh
./gen_bgp_filters.sh -R 24 -V C -A AS8345 -S 8345 -F 11 -P prefix-dsi-in -U 1800 -G acl-dsi-in -L 10.10.10.10/30
!
!Cisco IOS config:
!
conf t
no ip as-path access-list 11
ip as-path access-list 11 permit ^8345(_8345)*$
!
no ip prefix-list prefix-dsi-in
ip prefix-list prefix-dsi-in permit 84.244.48.0/20 le 24
ip prefix-list prefix-dsi-in permit 84.244.60.128/26
ip prefix-list prefix-dsi-in permit 91.185.32.0/19 le 24
ip prefix-list prefix-dsi-in permit 185.46.12.0/22 le 24
ip prefix-list prefix-dsi-in permit 195.206.32.0/19 le 24
!
no ip access-list extended acl-dsi-in
ip access-list extended acl-dsi-in
 permit ip 84.244.48.0 0.0.15.255 any
 permit ip 84.244.60.128 0.0.0.63 any
 permit ip 91.185.32.0 0.0.31.255 any
 permit ip 185.46.12.0 0.0.3.255 any
 permit ip 195.206.32.0 0.0.31.255 any
 permit ip 10.10.10.8 0.0.0.3 any
exit
!
no access-list 1800
access-list 1800 remark * URPF loose for AS8345 *
 permit 84.244.48.0 0.0.15.255
 permit 84.244.60.128 0.0.0.63
 permit 91.185.32.0 0.0.31.255
 permit 185.46.12.0 0.0.3.255
 permit 195.206.32.0 0.0.31.255
exit
!
!
end
!
```
The following example shows how to generate a BGP filter for Juniper:

```sh
./gen_bgp_filters.sh -R 24 -V J -A AS8345 -S 8345 -F 11 -P prefix-dsi-in -U 1800 -G acl-dsi-in -L 10.10.10.10/30
#
#JunOS config:
#
#configure
#
#load replace terminal
#
#
policy-options {
replace:
 as-path-group 11 {
  as-path a0 "^8345(8345)*$";
 }
}
#
#
policy-options {
replace:
  route-filter-list prefix-dsi-in {
    84.244.48.0/20 upto /24;
    84.244.60.128/26 exact;
    91.185.32.0/19 upto /24;
    185.46.12.0/22 upto /24;
    195.206.32.0/19 upto /24;
  }
}
#
#
firewall {
    family inet {
        replace:
        filter acl-dsi-in {
        /* Input filter for AS8345 */
            term TRUSTED-SOURCE {
                from {
                    source-address {
                        84.244.48.0/20;
                        84.244.60.128/26;
                        91.185.32.0/19;
                        185.46.12.0/22;
                        195.206.32.0/19;
                        10.10.10.8/30;
                    }
                }
                then {
                    accept;
                }
            }
            term DEFAULT {
                then discard;
            }
        }
    }
}
#
firewall {
    family inet {
        replace:
        filter acl-dsi-in {
        /* URPF loose for AS8345 */
            term TRUSTED-SOURCE-URPF {
                from {
                    source-address {
                        84.244.48.0/20;
                        84.244.60.128/26;
                        91.185.32.0/19;
                        185.46.12.0/22;
                        195.206.32.0/19;
                    }
                }
                then {
                    accept;
                }
            }
            term DEFAULT {
                then discard;
            }
        }
    }
}
#
# Press Ctrl+D
#
#
```

## Requirements

Ensure that the following tools are installed on your system:

- `bgpq4`: A tool for generating BGP prefix lists.
- `ipcalc`: A tool for calculating network addresses.

## Installation

Install the required tools using your package manager. For example, on a Debian-based system:

```sh
sudo apt-get install bgpq4 ipcalc
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request for any improvements or bug fixes.

## Contact

For any questions or suggestions, please open an issue on GitHub.

