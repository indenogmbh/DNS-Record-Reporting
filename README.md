# DNS-Record-Reporting
This PowerShell script checks MX, DMARC, SPF and NS records for a list of domains. It saves the results in a CSV file and handles errors and timeouts. Ideal for reporting on DNS and email security configurations for a large amount of domains.

## Prerequisites

- PowerShell 5.0 or higher
- A list of domains in a text file (`domains.txt`)

## How to Use

### 1. Download and Set Up

1. Clone this repository to your local machine or download the script file.
2. Prepare a `domains.txt` file containing a list of domains (one domain per line).

### 2. Running the Script

To execute the script, follow these steps:

1. Open **PowerShell**.
2. Navigate to the directory where the script is located.
3. Run the script with the following command:
   ```powershell
   .\DNS_Record_Query_Tool.ps1
   ```

### 3. Prompts and Inputs

The script will prompt you for the following inputs:

- **Full path to the `domains.txt` file**: Provide the absolute path to the file containing the list of domains.
- **Folder path for results file**: Provide the folder where the results CSV file will be saved. If the folder does not exist, the script will exit with an error.

### 4. Execution Time

Depending on the number of domains being processed and the DNS resolution times, the script might take **several minutes to hours** to complete. This is due to retries for DNS timeouts and the processing of potentially large lists of domains.

During execution, progress will be shown for each domain. Please be patient as the script resolves DNS records.

## Error Handling

- **DNS Resolution Failures**: If the script encounters DNS resolution issues, it will retry processing those domains.
- **Timeouts and Delays**: Domains experiencing timeouts may extend the execution time significantly. Be aware that the script will try again for failed queries, which could cause delays, especially with a large number of domains.

## Output

The script generates a CSV file containing the following columns:

- `Domain`: The domain name.
- `MX`: MX records found for the domain.
- `DMARC`: DMARC record for the domain.
- `DMARC_Subdomain`: DMARC records for subdomains (if any).
- `SPF`: SPF records for the domain.
- `SPF_Subdomain`: SPF records for subdomains (if any).
- `Nameserver`: The nameserver associated with the domain (if available).

## License

This project is licensed under the MIT License.
