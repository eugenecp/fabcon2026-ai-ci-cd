# Variable Library Template

This is an example structure for Variable Library artifacts.

## Structure

\\\
YourVariableLibrary.VariableLibrary/
├── variables.json ......... Variable definitions
└── settings.json .......... Library settings
\\\

## How Variable Substitution Works

1. **Source Control**: Store with empty values
\\\json
{
  "LakehouseId": "",
  "NotebookId": ""
}
\\\

2. **CD Pipeline**: Automatically replaces with actual GUIDs
\\\json
{
  "LakehouseId": "12345678-1234-1234-1234-123456789abc",
  "NotebookId": "87654321-4321-4321-4321-cba987654321"
}
\\\

3. **Per Environment**: Each environment gets workspace-specific IDs

See \scripts/substitute-variable-libraries.ps1\ for implementation.
