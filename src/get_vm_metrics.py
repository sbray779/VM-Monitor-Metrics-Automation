"""
Module to retrieve Azure Monitor metrics for VMs.
"""
import os
import json
from datetime import datetime, timedelta
from azure.identity import DefaultAzureCredential
from azure.mgmt.monitor import MonitorManagementClient
from azure.core.exceptions import HttpResponseError
from azure.storage.blob import BlobServiceClient


class VMMetricsRetriever:
    """Class to retrieve VM metrics from Azure Monitor."""
    
    # Define metric names for CPU, Memory, and Storage
    METRICS = {
        'cpu': 'Percentage CPU',
        'memory': 'Available Memory Bytes',
        'disk_read': 'Disk Read Bytes',
        'disk_write': 'Disk Write Bytes',
        'disk_read_ops': 'Disk Read Operations/Sec',
        'disk_write_ops': 'Disk Write Operations/Sec',
        'network_in': 'Network In Total',
        'network_out': 'Network Out Total'
    }
    
    def __init__(self, subscription_id=None, storage_account_name=None):
        """
        Initialize the VM Metrics Retriever.
        
        Args:
            subscription_id: Azure subscription ID. If not provided, uses AZURE_SUBSCRIPTION_ID env var.
            storage_account_name: Storage account name for writing metrics. If not provided, will use environment variable.
        """
        import os
        self.subscription_id = subscription_id or os.getenv('AZURE_SUBSCRIPTION_ID')
        if not self.subscription_id:
            raise ValueError("Subscription ID must be provided or set in AZURE_SUBSCRIPTION_ID environment variable")
        
        self.credential = DefaultAzureCredential()
        self.monitor_client = MonitorManagementClient(self.credential, self.subscription_id)
        
        # Initialize blob service client if storage account is provided
        self.storage_account_name = storage_account_name or os.getenv('AZURE_STORAGE_ACCOUNT_NAME')
        self.blob_service_client = None
        if self.storage_account_name:
            account_url = f"https://{self.storage_account_name}.blob.core.windows.net"
            self.blob_service_client = BlobServiceClient(account_url=account_url, credential=self.credential)
    
    def get_vm_metrics(self, vm_resource_id, hours_back=1, aggregations=None):
        """
        Retrieve metrics for a specific VM.
        
        Args:
            vm_resource_id: The full Azure resource ID of the VM.
            hours_back: Number of hours to look back for metrics (default: 1).
            aggregations: List of aggregation types (e.g., ['Average', 'Maximum']).
            
        Returns:
            Dictionary containing metrics data for the VM.
        """
        if aggregations is None:
            aggregations = ['Average', 'Maximum', 'Minimum']
        
        # Set time range
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=hours_back)
        
        # Prepare metrics list
        metric_names = list(self.METRICS.values())
        
        vm_metrics = {
            'vm_resource_id': vm_resource_id,
            'start_time': start_time.isoformat(),
            'end_time': end_time.isoformat(),
            'metrics': {}
        }
        
        try:
            # Query all metrics
            response = self.monitor_client.metrics.list(
                resource_uri=vm_resource_id,
                metricnames=','.join(metric_names),
                timespan=f"{start_time.isoformat()}/{end_time.isoformat()}",
                interval='PT5M',  # ISO 8601 duration format: 5 minutes
                aggregation=','.join(aggregations)
            )
            
            # Process each metric
            for metric in response.value:
                metric_data = {
                    'name': metric.name.value,
                    'unit': str(metric.unit),
                    'timeseries': []
                }
                
                for timeseries in metric.timeseries:
                    series_data = []
                    for data_point in timeseries.data:
                        point = {
                            'timestamp': data_point.time_stamp.isoformat() if data_point.time_stamp else None
                        }
                        
                        # Add available aggregations
                        if data_point.average is not None:
                            point['average'] = data_point.average
                        if data_point.maximum is not None:
                            point['maximum'] = data_point.maximum
                        if data_point.minimum is not None:
                            point['minimum'] = data_point.minimum
                        if data_point.total is not None:
                            point['total'] = data_point.total
                        if data_point.count is not None:
                            point['count'] = data_point.count
                        
                        series_data.append(point)
                    
                    metric_data['timeseries'].append({
                        'data': series_data,
                        'metadata': timeseries.metadatavalues if hasattr(timeseries, 'metadatavalues') else []
                    })
                
                vm_metrics['metrics'][metric.name.value] = metric_data
                
        except HttpResponseError as e:
            print(f"Error retrieving metrics for {vm_resource_id}: {e}")
            vm_metrics['error'] = str(e)
        
        return vm_metrics
    
    def get_metrics_for_vm_list(self, vms, hours_back=1):
        """
        Retrieve metrics for a list of VMs.
        
        Args:
            vms: List of VM dictionaries (from get_vms.py).
            hours_back: Number of hours to look back for metrics.
            
        Returns:
            List of dictionaries containing metrics for each VM.
        """
        all_metrics = []
        
        for vm in vms:
            print(f"Retrieving metrics for VM: {vm['name']}")
            metrics = self.get_vm_metrics(vm['id'], hours_back=hours_back)
            metrics['vm_name'] = vm['name']
            metrics['resource_group'] = vm['resource_group']
            all_metrics.append(metrics)
        
        return all_metrics
    
    def write_metrics_to_blob(self, metrics_data, container_name="vm-metrics-output"):
        """
        Write metrics data to blob storage.
        
        Args:
            metrics_data: Dictionary containing metrics data to write.
            container_name: Name of the blob container (default: "vm-metrics-output").
            
        Returns:
            Dictionary with write status and blob URL.
        """
        if not self.blob_service_client:
            raise ValueError("Blob service client not initialized. Provide storage_account_name.")
        
        try:
            # Ensure container exists
            container_client = self.blob_service_client.get_container_client(container_name)
            try:
                container_client.get_container_properties()
            except Exception:
                # Container doesn't exist, create it
                container_client.create_container()
            
            # Generate blob name with timestamp
            timestamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
            vm_count = metrics_data.get('vm_count', 0)
            blob_name = f"vm-metrics-{timestamp}-{vm_count}vms.json"
            
            # Convert metrics to JSON
            json_data = json.dumps(metrics_data, default=str, indent=2)
            
            # Upload to blob
            blob_client = container_client.get_blob_client(blob_name)
            blob_client.upload_blob(json_data, overwrite=True)
            
            blob_url = blob_client.url
            
            return {
                "success": True,
                "blob_name": blob_name,
                "blob_url": blob_url,
                "container": container_name,
                "size_bytes": len(json_data)
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": str(e)
            }
    
    def summarize_metrics(self, vm_metrics):
        """
        Print a summary of VM metrics.
        
        Args:
            vm_metrics: Metrics data for a single VM.
        """
        print(f"\nMetrics Summary for VM: {vm_metrics.get('vm_name', 'Unknown')}")
        print(f"Resource Group: {vm_metrics.get('resource_group', 'Unknown')}")
        print(f"Time Range: {vm_metrics['start_time']} to {vm_metrics['end_time']}")
        print("-" * 80)
        
        if 'error' in vm_metrics:
            print(f"Error: {vm_metrics['error']}")
            return
        
        for metric_name, metric_data in vm_metrics['metrics'].items():
            print(f"\nMetric: {metric_name} ({metric_data['unit']})")
            
            # Calculate aggregate statistics across all timeseries
            all_averages = []
            all_maximums = []
            all_minimums = []
            
            for timeseries in metric_data['timeseries']:
                for point in timeseries['data']:
                    if 'average' in point and point['average'] is not None:
                        all_averages.append(point['average'])
                    if 'maximum' in point and point['maximum'] is not None:
                        all_maximums.append(point['maximum'])
                    if 'minimum' in point and point['minimum'] is not None:
                        all_minimums.append(point['minimum'])
            
            if all_averages:
                print(f"  Average: {sum(all_averages) / len(all_averages):.2f}")
            if all_maximums:
                print(f"  Peak: {max(all_maximums):.2f}")
            if all_minimums:
                print(f"  Minimum: {min(all_minimums):.2f}")


def main():
    """Main function to demonstrate metrics retrieval."""
    from get_vms import VMRetriever
    import os
    
    # Get VMs first
    resource_group = os.getenv('AZURE_RESOURCE_GROUP')
    vm_retriever = VMRetriever()
    
    if resource_group:
        vms = vm_retriever.get_vms(resource_group=resource_group)
    else:
        vms = vm_retriever.get_vms()
    
    if not vms:
        print("No VMs found.")
        return
    
    # Get metrics for VMs
    metrics_retriever = VMMetricsRetriever()
    all_metrics = metrics_retriever.get_metrics_for_vm_list(vms, hours_back=24)
    
    # Print summaries
    for vm_metrics in all_metrics:
        metrics_retriever.summarize_metrics(vm_metrics)
        print("\n" + "=" * 80 + "\n")
    
    return all_metrics


if __name__ == "__main__":
    main()
