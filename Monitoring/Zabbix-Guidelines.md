Zabbix Guidelines
=================
This document is intended to a guide to running Zabbix in a sensible way in production environments.

Aims
----
These should be the overall aims for anyone considering a new Zabbix installation.

* __High availability__ (Zabbix should be available all of the time, or as close as we can manage)
* __High performance__ (Zabbix should be able to monitor everything you intend to have, even with 24 months worth of history in the DB)
* __Operational simplicity__ (as simple as possible anyway)
* __Consistency__ (Conventions should be applied and observed across the board to make this as easy to understand as possible)
* __Repeatability__ (Various components should be able to be rebuilt automatically without requiring hand-crafted configurations)
* __Longevity__ (The installation should be able to run for the next 2 years without requiring a massive overhaul)

Guidelines
----------
The following sections carry some advice for how to approach each part of your Zabbix installation.

### The server database
The database for the Zabbix server is core to the entire platform. Zabbix's architecture doesn't allow for multiple active servers, which means that our efforts need to be focused here.
* __MySQL__ is the "default" database engine for Zabbix, and I suggest you stick with it.
* My first choice would be to run a __multi-AZ RDS__ for the Zabbix database. If you make this choice, be careful to select a version of MySQL that Zabbix is known to work with.
* The database will start off small, but will increase in size constantly until all of your data has reached its maximum retention time, or you truncate the history tables.
* I was able to monitor 500 instances and retain 12 months worth of history with a 50GB database, but this was only possible because I was very __careful about moving data from history to trends, and reducing check frequencies__.
* For safety's sake start with at least __100GB__.

### The Zabbix Server
The "server" really refers to the Zabbix-Server process, but this needs to run somewhere so we can call that instance the "server" too.
* Make sure that the installation and configuration of the server is __FULLY automated__. Probably the best way is to create an AMI or an EBS snapshot once the software is installed. This means you could then run this in an autoscaling group, and know that whenever you decide to rebuild this instance (or it dies for whatever reason), a new one will come back as quickly as possible and start working again.
* In general I don't recommend changing configurations from the default unless you know that you have to do it. The configurations I DO suggest changing for the Zabbix-server process are:
  - StartTrappers=10
  - StartHTTPPollers=10
  - CacheSize=64M
  - TrendCacheSize=8M
* The server needs to be accessible to other parts of the system: Agents, and Proxies (if you're going down this path)

### The Zabbix Frontend
The "frontend" is quite a simple component. It's just a LAMP app, and sits happily behind a load-balancer.
* Its worth having 2 of these, running behind a load-balancer. They don't have to be big instances at all.
* Its much easier to have the load-balancer terminate the SSL, rather than having to install your certs on the frontend boxes themselves.
* The frontend boxes only really need to know where to find the database.
* You should provision a different MySQL user for the frontend than the one you're using for the server. This can help you debug issues in the future.

### Zabbix Proxies
Proxies are one of the best features of Zabbix. This is what they call "distributed monitoring" in the documentation. Proxies are a good way to achieve reliable remote monitoring, and they also take a lot of processing load away from the server. It works like this:
* Named "proxies" are defined in the Zabbix admin console.
* Each "host" in the Zabbix database can be assigned to one of these named proxies.
* "Zabbix Proxy" is another package/daemon, installed on another instance.
* Each Zabbix Proxy is configured to know what its name is (according to the Zabbix Server), and the address of the Zabbix Server to connect to.
* When a Zabbix Proxy connects to the server and tells it the configured name, the Zabbix Server will look in the database and find a list of checks the proxy should be responsible for. This list of hosts and checks is returned to the proxy so it can cache it in a local database.
* The Zabbix proxy can deal with both "Active" and "Passive" checks. It will perform passive checks on the configured list of hosts (agents), just the same as a Zabbix Server.
* The Zabbix proxy can also accept "Active" check data from hosts / agents.
* According to the proxy configuration it will regularly contact the Zabbix Server and upload all of the results it has collected since last time. If this fails, it will keep hold of the data and try again (this helps us to deal with unreliable WAN/VPN connections or a server that is temporarily offline, without losing any data).
* Although the documentation doesn't mention this, I have successfully run proxies in pairs. In this configuration each proxy should have the same "name" defined. This means they'll both connect to the server and get the same list of hosts & checks. Your agents should be configured to work with both local proxies.
* You should define some triggers on the Zabbix server that will raise an alert if a proxy hasn't connected within the last 5/10 minutes (particularly important if you're running entirely "active" checks).

### Templates
Although Zabbix DOES allow you to configure items / triggers / graphs etc against individual hosts, this is a terrible idea because you'll end up having to copy these around each time you build a similar host. Instead, items / triggers / graphs etc can be defined once and for all in "Templates", which can be applied to hosts (or groups).
* __You should never end up defining an item / trigger / graph more than once__. Put these into templates instead.
* Each host can belong to many templates, but this gets complicated when it comes to auto-discovery or auto-registration of hosts.
* Instead, break your list of hosts up into "roles" and make one template per role.
* Build each role template by linking in whatever other templates you need, for example the "zabbix-frontend" role template could include sub-templates like "OS - Linux" + "App - Apache".
* This means you can re-cycle the "OS - Linux" + "App - Apache" templates as many times as you like.

### Retention
The size of your database (and workload on the server) can be calculated as `N * (H + T) * F` (__N__: number-of-items-monitored, __H__: history-retention, __T__: trends-retention, __F__: check-frequency).

* "__History__" is raw data as it was collected from the agents. Setting 7-days history for an item means that every value recorded will be kept for 7 days before being down-sampled into a trend, and purged from the history tables.
* "__Trends__" is pre-aggregated data derived from history. The "housekeeping" processes take the history, down-sample it into the trends tables, and clean it out. Keeping your history as trends is usually just as effective as history, but uses a fraction of the storage.
* When you look at historic graphs the data is automatically combined from history and trends (you'll probably notice the lower resolution of the trends data).
* Always try to __reduce the frequency of your monitoring to extend the life of your database__. Of course, you still need some history for diagnosing performance issues and capacity planning. Here are some rules-of-thumb:
  - FileSystems (used): F:300s, H:30d, T:1y
  - FileSystems (total): F: 900S, H:7d, T:1y
  - CPU: F:60s, H:7d, T:90d
  - Memory: F: 300s, H:7d, T:90d

### User accounts & groups
If you DO end up needing to provision accounts for individual users, I strongly suggest that you don't define any actions against specific accounts - use groups instead.
* In all but the most ridiculous environments it's usually OK to provision generic unprivileged accounts for administrative groups of people to see the dashboard.
* You'll also need some of these accounts to leave logged in to screens dotted around the office.

### Alerting
Although Zabbix CAN handle alerts & escalations, I strongly advise you to ignore this and simply forward notifications to an external service like PagerDuty, and manage your alerts & rotas from there. It is much easier than provisioning user accounts on Zabbix, and needs to be done anyway.

### Agents
* Any custom user-parameters should be grouped into discrete files for each application. This means you can copy in whatever user-parameter files are needed for the apps installed on a monitored host.
* Configure each agent with the addresses of all the proxies responsible for it, for both the "Server" and "ServerActive" options.

### "Active" (push) vs "Passive" (pull) monitoring
I always prefer to use PUSH monitoring wherever possible.
* Errors are raised upstream immediately
* Statistics are pre-calculated on the agent, then delivered upstream in batches. This means that the server/proxy doesn't have to wait for the agent to calculate everything.
* Push monitoring minimises the number of times an agent has to calculate items. In a passive configuration each proxy/server would connect to an agent and ask for the same data.
* Push monitoring can be used to achieve automatic discovery of agents.

### General advice
* Don't include items that will never be available on a host - these are still checked from time to time by zabbix, so they use resources.
* The default templates retrieve a lot of data, and they do it at high frequency. If you tried to monitor 500 servers with this config you'd very quickly fill up the database. You shouldn't ask "how often can I check this"... instead ask "__how infrequently can I check this and still get the monitoring I need__".
