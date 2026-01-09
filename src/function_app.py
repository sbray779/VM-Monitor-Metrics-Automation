"""
Azure Function to retrieve VM metrics from Azure Monitor.
"""
import azure.functions as func
import json
import logging
import os
from datetime import datetime
from get_vms import VMRetriever
from get_vm_metrics import VMMetricsRetriever

app = func.FunctionApp()


@app.function_name(name="GetVMMetrics")
@app.route(route="vm-metrics", methods=["GET", "POST"], auth_level=func.AuthLevel.FUNCTION)
def get_vm_metrics(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP triggered function to retrieve VM metrics.
    
    Query Parameters or JSON Body:
    - subscription_id: (optional) Azure subscription ID
    - resource_group: (optional) Filter by resource group
    - hours_back: (optional) Number of hours to look back (default: 24)
    
    Returns:
        JSON response with VM list and metrics
    """
    logging.info('GetVMMetrics function triggered')
    
    try:
        # Parse input parameters
        if req.method == "POST":
            try:
                req_body = req.get_json()
            except ValueError:
                req_body = {}
        else:
            req_body = {}
        
        # Support both single subscription_id and array of subscription_ids
        subscription_id = req.params.get('subscription_id') or req_body.get('subscription_id')
        subscription_ids = req.params.get('subscription_ids') or req_body.get('subscription_ids')
        
        # Convert single subscription_id to array format
        if subscription_ids:
            if isinstance(subscription_ids, str):
                # Handle comma-separated string
                subscription_ids = [s.strip() for s in subscription_ids.split(',')]
        elif subscription_id:
            subscription_ids = [subscription_id]
        else:
            subscription_ids = None
        
        resource_group = req.params.get('resource_group') or req_body.get('resource_group')
        hours_back = int(req.params.get('hours_back') or req_body.get('hours_back', 24))
        page_size = int(req.params.get('page_size') or req_body.get('page_size', 100))
        skip_token = req.params.get('skip_token') or req_body.get('skip_token')
        
        logging.info(f"Parameters - subscription_ids: {subscription_ids}, resource_group: {resource_group}, hours_back: {hours_back}, page_size: {page_size}")
        
        # Step 1: Retrieve VMs with pagination
        logging.info("Retrieving VMs from Azure Resource Graph...")
        vm_retriever = VMRetriever(subscription_ids=subscription_ids)
        
        if resource_group:
            vms, next_skip_token = vm_retriever.get_vms(resource_group=resource_group, page_size=page_size, skip_token=skip_token)
            logging.info(f"Found {len(vms)} VMs in resource group: {resource_group} (page {page_size})")
        else:
            vms, next_skip_token = vm_retriever.get_vms(page_size=page_size, skip_token=skip_token)
            logging.info(f"Found {len(vms)} VMs in subscription (page {page_size})")
        
        if not vms:
            return func.HttpResponse(
                json.dumps({"error": "No VMs found", "vms": [], "metrics": []}),
                mimetype="application/json",
                status_code=200
            )
        
        # Step 2: Retrieve Metrics
        logging.info(f"Retrieving metrics for {len(vms)} VMs...")
        
        # Get storage account name from environment variable
        storage_account_name = req.params.get('storage_account') or req_body.get('storage_account') or os.environ.get('AZURE_STORAGE_ACCOUNT_NAME')
        
        # Use first subscription for metrics retrieval (metrics are retrieved per-VM anyway)
        primary_subscription = subscription_ids[0] if subscription_ids else None
        metrics_retriever = VMMetricsRetriever(subscription_id=primary_subscription, storage_account_name=storage_account_name)
        all_metrics = metrics_retriever.get_metrics_for_vm_list(vms, hours_back=hours_back)
        
        # Prepare response with pagination info
        response_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "vm_count": len(vms),
            "subscription_ids": subscription_ids or ["default"],
            "resource_group": resource_group or "all",
            "hours_back": hours_back,
            "page_size": page_size,
            "has_more": next_skip_token is not None,
            "skip_token": next_skip_token,
            "vms": vms,
            "metrics": all_metrics
        }
        
        # Step 3: Write metrics to blob storage
        blob_write_result = None
        if storage_account_name:
            try:
                logging.info("Writing metrics to blob storage...")
                blob_write_result = metrics_retriever.write_metrics_to_blob(response_data)
                if blob_write_result.get('success'):
                    logging.info(f"Successfully wrote metrics to blob: {blob_write_result.get('blob_name')}")
                    response_data['blob_storage'] = blob_write_result
                else:
                    logging.warning(f"Failed to write metrics to blob: {blob_write_result.get('error')}")
                    response_data['blob_storage'] = {"success": False, "error": blob_write_result.get('error')}
            except Exception as e:
                logging.error(f"Error writing to blob storage: {str(e)}")
                response_data['blob_storage'] = {"success": False, "error": str(e)}
        
        logging.info("Successfully retrieved VM metrics")
        
        return func.HttpResponse(
            json.dumps(response_data, default=str),
            mimetype="application/json",
            status_code=200
        )
        
    except ValueError as e:
        error_msg = f"Configuration error: {str(e)}"
        logging.error(error_msg)
        return func.HttpResponse(
            json.dumps({"error": error_msg}),
            mimetype="application/json",
            status_code=400
        )
    
    except Exception as e:
        error_msg = f"Error retrieving VM metrics: {str(e)}"
        logging.error(error_msg, exc_info=True)
        return func.HttpResponse(
            json.dumps({"error": error_msg}),
            mimetype="application/json",
            status_code=500
        )


@app.function_name(name="GetVMsOnly")
@app.route(route="vms", methods=["GET", "POST"], auth_level=func.AuthLevel.FUNCTION)
def get_vms_only(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP triggered function to retrieve VM list only (no metrics).
    
    Query Parameters or JSON Body:
    - subscription_id: (optional) Azure subscription ID
    - resource_group: (optional) Filter by resource group
    
    Returns:
        JSON response with VM list
    """
    logging.info('GetVMsOnly function triggered')
    
    try:
        # Parse input parameters
        if req.method == "POST":
            try:
                req_body = req.get_json()
            except ValueError:
                req_body = {}
        else:
            req_body = {}
        
        # Support both single subscription_id and array of subscription_ids
        subscription_id = req.params.get('subscription_id') or req_body.get('subscription_id')
        subscription_ids = req.params.get('subscription_ids') or req_body.get('subscription_ids')
        
        # Convert single subscription_id to array format
        if subscription_ids:
            if isinstance(subscription_ids, str):
                # Handle comma-separated string
                subscription_ids = [s.strip() for s in subscription_ids.split(',')]
        elif subscription_id:
            subscription_ids = [subscription_id]
        else:
            subscription_ids = None
        
        resource_group = req.params.get('resource_group') or req_body.get('resource_group')
        page_size = int(req.params.get('page_size') or req_body.get('page_size', 100))
        skip_token = req.params.get('skip_token') or req_body.get('skip_token')
        
        logging.info(f"Parameters - subscription_ids: {subscription_ids}, resource_group: {resource_group}, page_size: {page_size}")
        
        # Retrieve VMs with pagination
        vm_retriever = VMRetriever(subscription_ids=subscription_ids)
        
        if resource_group:
            vms, next_skip_token = vm_retriever.get_vms(resource_group=resource_group, page_size=page_size, skip_token=skip_token)
            logging.info(f"Found {len(vms)} VMs in resource group: {resource_group} (page {page_size})")
        else:
            vms, next_skip_token = vm_retriever.get_vms(page_size=page_size, skip_token=skip_token)
            logging.info(f"Found {len(vms)} VMs in subscription (page {page_size})")
        
        response_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "vm_count": len(vms),
            "subscription_ids": subscription_ids or ["default"],
            "resource_group": resource_group or "all",
            "page_size": page_size,
            "has_more": next_skip_token is not None,
            "skip_token": next_skip_token,
            "vms": vms
        }
        
        return func.HttpResponse(
            json.dumps(response_data, default=str),
            mimetype="application/json",
            status_code=200
        )
        
    except ValueError as e:
        error_msg = f"Configuration error: {str(e)}"
        logging.error(error_msg)
        return func.HttpResponse(
            json.dumps({"error": error_msg}),
            mimetype="application/json",
            status_code=400
        )
    
    except Exception as e:
        error_msg = f"Error retrieving VMs: {str(e)}"
        logging.error(error_msg, exc_info=True)
        return func.HttpResponse(
            json.dumps({"error": error_msg}),
            mimetype="application/json",
            status_code=500
        )
