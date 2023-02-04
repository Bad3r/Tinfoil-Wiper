# Tinfoil Wiper 🧹
Tinfoil Wiper is a secure NVMe SSD wiping tool written in Bash. It securely erases the data on an NVMe SSD by overwriting the disk multiple times with random data, using the Gutmann method.

### Requirements

  * A UNIX-like operating system
  * cryptsetup and hexdump
  * Root permissions


### Usage

Run the script as root and provide the path to the NVMe SSD as an argument. For example, to wipe `/dev/nvme0n1`, run:

```bash
sudo tinfoil_wiper /dev/nvme0n1
```

### How it works

#### LUKS2 Encryption

The script creates a LUKS2 encrypted volume on the specified NVMe SSD. A random password is generated to encrypt the volume, which is then wiped using the Gutmann method. The LUKS2 volume is then closed, and the NVMe SSD is wiped one final time with zeros data.

#### Verification
After wiping the disk, the script verifies that the data has been securely erased by reading a small sample of data from the NVMe SSD and checking for any non-zero bytes. If the verification fails, an error message is displayed.

#### Output

The output of the script displays the progress of the wiping process, including the iteration of the Gutmann method and the result of the verification. If the wiping is successful, a message is displayed indicating that the NVMe SSD has been securely wiped.

```Bash
:: Wiping /dev/nvme0n1...
:: Generating a random password..
:: password: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
:: Creating LUKS2 encrypted volume on /dev/nvme0n1
:: Wiping LUKS2 encrypted volume..
:: Source: /dev/random...
:: Gutmann iteration: 1/35
:: Gutmann iteration: 2/35
...
:: Gutmann iteration: 35/35
:: Closing LUKS2 encrypted volume
:: /dev/nvme0n1 securely wiped.
```



### Notes
* Wiping the data on an SSD with this script is a destructive and irreversible process. Be sure to backup all important data before running the script.
* This script is provided as-is, with no guarantees or warranties of any kind. Use at your own risk.
