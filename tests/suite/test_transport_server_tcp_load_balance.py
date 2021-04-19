import pytest
import re
import time
import socket

from settings import TEST_DATA
from suite.resources_utils import (
    wait_before_test,
    patch_deployment_from_yaml,
    create_items_from_yaml,
    get_ingress_nginx_template_conf,
    get_ts_nginx_template_conf,
    create_service_from_yaml,
    delete_service,
    scale_deployment
)
from suite.custom_resources_utils import (
    patch_ts
)


@pytest.mark.ts
@pytest.mark.parametrize(
    "crd_ingress_controller, transport_server_setup",
    [
        (
            {
                "type": "complete",
                "extra_args":
                    [
                        "-global-configuration=nginx-ingress/nginx-configuration",
                        "-enable-leader-election=false"
                    ]
            },
            {"example": "transport-server-tcp-load-balance", "app_type": "simple"},
        )
    ],
    indirect=True,
)
class TestTransportServerTcpLoadBalance:

    def restore_transport_server(self, kube_apis, transport_server_setup) -> None:
        """
        Function to revert a TransportServer resource to a valid state.
        """
        transport_server_file = f"{TEST_DATA}/transport-server-status/standard/transport-server.yaml"
        patch_ts(kube_apis.custom_objects, transport_server_setup.name, transport_server_file, transport_server_setup.namespace)

    @pytest.mark.sean
    def test_number_of_replicas(
        self, kube_apis, crd_ingress_controller, transport_server_setup, ingress_controller_prerequisites
    ):
        """
        The load balancing of TCP should result in 4 servers to match the 4 replicas of a service.
        """
        original = scale_deployment(kube_apis.apps_v1_api, "tcp-service", transport_server_setup.namespace, 4)

        wait_before_test()

        result_conf = get_ts_nginx_template_conf(
            kube_apis.v1,
            transport_server_setup.namespace,
            transport_server_setup.name,
            transport_server_setup.ingress_pod_name,
            ingress_controller_prerequisites.namespace
        )

        pattern = 'server .*;'
        num_servers = len(re.findall(pattern, result_conf))

        assert num_servers is 4

        scale_deployment(kube_apis.apps_v1_api, "tcp-service", transport_server_setup.namespace, original)

    def test_tcp_request_load_balanced(
            self, kube_apis, crd_ingress_controller, transport_server_setup
    ):
        """
        Requests to the load balanced TCP service should result in responses from 3 different endpoints.
        """
        node_port_file = f"{TEST_DATA}/transport-server-tcp-load-balance/standard/node-port.yaml"
        node_port_name = create_service_from_yaml(
            kube_apis.v1,
            transport_server_setup.namespace,
            node_port_file,
        )

        wait_before_test(3)

        node_port_service = kube_apis.v1.read_namespaced_service(node_port_name, transport_server_setup.namespace)
        port = node_port_service.spec.ports[0].node_port
        host = transport_server_setup.public_endpoint.public_ip

        print(f"sending tcp requests to: {host}:{port}")

        endpoints = {}
        for i in range(20):
            client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            client.connect((host, port))
            response = client.recv(4096)
            endpoint = response.decode()
            print(f' req number {i}; response: {endpoint}')
            if endpoint not in endpoints:
                endpoints[endpoint] = 1
            else:
                endpoints[endpoint] = endpoints[endpoint] + 1

        assert len(endpoints) is 3

        delete_service(kube_apis.v1, node_port_name, transport_server_setup.namespace)

        self.restore_transport_server(kube_apis, transport_server_setup)


