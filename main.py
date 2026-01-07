"""
Main script to retrieve VMs and their metrics from Azure.
"""
import os
import json
from datetime import datetime
from get_vms import VMRetriever
from get_vm_metrics import VMMetricsRetriever
from dotenv import load_dotenv


def save_to_json(data, filename):
    """
    Save data to a JSON file.
    
    Args:
        data: Data to save.
        filename: Output filename.
    """
    with open(filename, 'w') as f:
        json.dump(data, f, indent=2, default=str)
    print(f"Data saved to {filename}")


def main():
    """Main execution function."""
    # Load environment variables
    load_dotenv()
    
    # Configuration
    resource_group = os.getenv('AZURE_RESOURCE_GROUP')
    hours_back = int(os.getenv('METRICS_HOURS_BACK', '24'))
    
    print("=" * 80)
    print("Azure VM Monitor Metrics Automation")
    print("=" * 80)
    
    # Step 1: Retrieve VMs
    print("\n[Step 1] Retrieving VMs from Azure Resource Graph...")
    vm_retriever = VMRetriever()
    
    if resource_group:
        print(f"Filtering by resource group: {resource_group}")
        vms = vm_retriever.get_vms(resource_group=resource_group)
    else:
        print("Retrieving all VMs from subscription")
        vms = vm_retriever.get_vms()
    
    vm_retriever.print_vms(vms)
    
    if not vms:
        print("\nNo VMs found. Exiting.")
        return
    
    # Save VM list
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    vm_list_file = f"vm_list_{timestamp}.json"
    save_to_json(vms, vm_list_file)
    
    # Step 2: Retrieve Metrics
    print(f"\n[Step 2] Retrieving metrics for {len(vms)} VMs...")
    print(f"Time range: Last {hours_back} hours")
    
    metrics_retriever = VMMetricsRetriever()
    all_metrics = metrics_retriever.get_metrics_for_vm_list(vms, hours_back=hours_back)
    
    # Display summaries
    print("\n" + "=" * 80)
    print("METRICS SUMMARY")
    print("=" * 80)
    
    for vm_metrics in all_metrics:
        metrics_retriever.summarize_metrics(vm_metrics)
        print("\n" + "-" * 80 + "\n")
    
    # Save metrics data
    metrics_file = f"vm_metrics_{timestamp}.json"
    save_to_json(all_metrics, metrics_file)
    
    print("\n" + "=" * 80)
    print("Execution completed successfully!")
    print(f"VM list saved to: {vm_list_file}")
    print(f"Metrics data saved to: {metrics_file}")
    print("=" * 80)


if __name__ == "__main__":
    main()
