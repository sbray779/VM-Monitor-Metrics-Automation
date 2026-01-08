"""
Module to retrieve Azure VMs using Azure Resource Graph.
"""
import os
from azure.identity import DefaultAzureCredential
from azure.mgmt.resourcegraph import ResourceGraphClient
from azure.mgmt.resourcegraph.models import QueryRequest
from dotenv import load_dotenv

# Load environment variables
load_dotenv()


class VMRetriever:
    """Class to retrieve VMs from Azure using Resource Graph."""
    
    def __init__(self, subscription_id=None):
        """
        Initialize the VM Retriever.
        
        Args:
            subscription_id: Azure subscription ID. If not provided, uses AZURE_SUBSCRIPTION_ID env var.
        """
        self.subscription_id = subscription_id or os.getenv('AZURE_SUBSCRIPTION_ID')
        if not self.subscription_id:
            raise ValueError("Subscription ID must be provided or set in AZURE_SUBSCRIPTION_ID environment variable")
        
        self.credential = DefaultAzureCredential()
        self.resource_graph_client = ResourceGraphClient(self.credential)
    
    def get_vms(self, resource_group=None):
        """
        Retrieve all VMs in the subscription or a specific resource group.
        
        Args:
            resource_group: Optional. If provided, filters VMs to this resource group.
            
        Returns:
            List of VM dictionaries with relevant properties.
        """
        # Build the query
        if resource_group:
            query = f"""
            Resources
            | where type == "microsoft.compute/virtualmachines"
            | where resourceGroup =~ "{resource_group}"
            | project id, name, resourceGroup, location, properties
            """
        else:
            query = """
            Resources
            | where type == "microsoft.compute/virtualmachines"
            | project id, name, resourceGroup, location, properties
            """
        
        # Create the query request
        query_request = QueryRequest(
            subscriptions=[self.subscription_id],
            query=query
        )
        
        # Execute the query
        response = self.resource_graph_client.resources(query_request)
        
        # Extract VM data
        vms = []
        for row in response.data:
            vm = {
                'id': row['id'],
                'name': row['name'],
                'resource_group': row['resourceGroup'],
                'location': row['location'],
                'properties': row.get('properties', {})
            }
            vms.append(vm)
        
        return vms
    
    def print_vms(self, vms):
        """
        Print VM information in a readable format.
        
        Args:
            vms: List of VM dictionaries.
        """
        print(f"\nFound {len(vms)} virtual machines:")
        print("-" * 80)
        for vm in vms:
            print(f"Name: {vm['name']}")
            print(f"Resource Group: {vm['resource_group']}")
            print(f"Location: {vm['location']}")
            print(f"Resource ID: {vm['id']}")
            print("-" * 80)


def main():
    """Main function to demonstrate VM retrieval."""
    # Get resource group from environment if specified
    resource_group = os.getenv('AZURE_RESOURCE_GROUP')
    
    # Initialize retriever
    retriever = VMRetriever()
    
    # Get VMs
    if resource_group:
        print(f"Retrieving VMs from resource group: {resource_group}")
        vms = retriever.get_vms(resource_group=resource_group)
    else:
        print("Retrieving all VMs from subscription")
        vms = retriever.get_vms()
    
    # Print results
    retriever.print_vms(vms)
    
    return vms


if __name__ == "__main__":
    main()
