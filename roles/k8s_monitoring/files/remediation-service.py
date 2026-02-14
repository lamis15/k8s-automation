#!/usr/bin/env python3
from flask import Flask, request, jsonify
import subprocess
import json
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

REMEDIATION_ACTIONS = {
    "HighCPUUsage": {
        "action": "scale_deployment",
        "deployment": "demo-app",
        "namespace": "default",
        "replicas": 5
    },
    "HighMemoryUsage": {
        "action": "restart_deployment",
        "deployment": "demo-app",
        "namespace": "default"
    },
    "PodCrashLooping": {
        "action": "restart_pod",
        "namespace": "default"
    },
    "HighDiskUsage": {
        "action": "cleanup_logs",
        "node": "auto-detect"
    }
}

def run_kubectl(cmd):
    """Execute kubectl command"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        logging.info(f"Command: {cmd}")
        logging.info(f"Output: {result.stdout}")
        return result.returncode == 0, result.stdout
    except Exception as e:
        logging.error(f"Error: {e}")
        return False, str(e)

def scale_deployment(deployment, namespace, replicas):
    """Scale deployment to specified replicas"""
    cmd = f"kubectl scale deployment {deployment} -n {namespace} --replicas={replicas}"
    return run_kubectl(cmd)

def restart_deployment(deployment, namespace):
    """Restart deployment"""
    cmd = f"kubectl rollout restart deployment {deployment} -n {namespace}"
    return run_kubectl(cmd)

def restart_pod(pod_name, namespace):
    """Delete pod to force restart"""
    cmd = f"kubectl delete pod {pod_name} -n {namespace}"
    return run_kubectl(cmd)

def cleanup_logs(node):
    """Clean up logs on node"""
    # This is a simplified example
    logging.info(f"Would clean logs on {node}")
    return True, "Log cleanup simulated"

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"}), 200

@app.route('/webhook', methods=['POST'])
def webhook():
    """Receive alerts from Alertmanager and take action"""
    try:
        data = request.json
        logging.info(f"Received webhook: {json.dumps(data, indent=2)}")
        
        alerts = data.get('alerts', [])
        actions_taken = []
        
        for alert in alerts:
            if alert['status'] != 'firing':
                continue
                
            alert_name = alert['labels'].get('alertname')
            instance = alert['labels'].get('instance', 'unknown')
            
            logging.info(f"Processing alert: {alert_name} on {instance}")
            
            if alert_name in REMEDIATION_ACTIONS:
                remediation = REMEDIATION_ACTIONS[alert_name]
                action_type = remediation['action']
                
                if action_type == 'scale_deployment':
                    success, output = scale_deployment(
                        remediation['deployment'],
                        remediation['namespace'],
                        remediation['replicas']
                    )
                    actions_taken.append({
                        "alert": alert_name,
                        "action": f"Scaled {remediation['deployment']} to {remediation['replicas']} replicas",
                        "success": success,
                        "output": output
                    })
                
                elif action_type == 'restart_deployment':
                    success, output = restart_deployment(
                        remediation['deployment'],
                        remediation['namespace']
                    )
                    actions_taken.append({
                        "alert": alert_name,
                        "action": f"Restarted deployment {remediation['deployment']}",
                        "success": success,
                        "output": output
                    })
                
                elif action_type == 'restart_pod':
                    pod_name = alert['labels'].get('pod')
                    if pod_name:
                        success, output = restart_pod(pod_name, remediation['namespace'])
                        actions_taken.append({
                            "alert": alert_name,
                            "action": f"Restarted pod {pod_name}",
                            "success": success,
                            "output": output
                        })
        
        return jsonify({
            "status": "processed",
            "actions": actions_taken
        }), 200
    
    except Exception as e:
        logging.error(f"Error processing webhook: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
