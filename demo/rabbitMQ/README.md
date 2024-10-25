# Debug:

## Get rabbitmqadmin from the rabbitmq host:
Requires python
```BASH
$ curl http://rmq-svc.rabbitmq:15672/cli/rabbitmqadmin --output rabbitmqadmin
chmod +x rabbitmqadmin
mv rabbitmqadmin /usr/local/bin/
```

## List queues and exchanges
```BASH
$ rabbitmqadmin -u user -p password -H rmq-svc.rabbitmq list exchanges

$ rabbitmqadmin -u user -p password -H rmq-svc.rabbitmq list queues
```
