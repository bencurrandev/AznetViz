# Az Network Vizualiser

A Powershell script that will traverse your Azure subscription and create a diagram of all the network resources in your subscription. This will include information such as the resource group, resource name, resource type, location, IP address ranges, subnets, and more. Additionally, it will also show the relationships between the resources.

## Installation

To install this project, you need to have Powershell Core and the Az Powershell module installed on your machine. Then, follow these steps:

- Clone this repository: `git clone https://github.com/bencurrandev/AzNetViz.git`
- Go to the project directory: `cd AzNetViz`

## Usage

- Login to Azure: `Connect-AzAccount` (you will be prompted to login to Azure) *Note: If you are a member of multiple AzureAD tenants, you will need to specify the tenant you want to use: `Connect-AzAccount -TenantId <tenant-id>`*
- Run the script: `.\AzNetViz.ps1 -OutputFile <output-file-name> -OutputFormat <output-file-format>`
- Open the output file in your preferred image viewer

### Parameters

- `-OutputFile` - (required) The name of the output file. This can be a relative or absolute path. If no path is specified, the file will be saved in the current directory. 
- `-OutputFormat` - (optional) The format of the output file. The following list of formats are supported:
    - svg (default)
    - png
    - jpg
    - gif
    - imap
    - cmapx
    - jp2
    - json
    - pdf
    - plain
    - dot

## Contributing

To contribute to this project, you can do the following:

- Fork this repository and create a new branch for your feature or bug fix.
- Make your changes and commit them with a descriptive message.
- Push your branch to your fork and create a pull request to the main repository.
- Wait for your pull request to be reviewed and merged.

## Issues and Features

To report issues or request features for this project, you can do the following:

- Go to the issues tab of this repository and create a new issue.
- Fill out the issue template with the relevant information and submit it.
- Wait for a response from the project maintainer or other contributors.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.