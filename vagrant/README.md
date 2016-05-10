# Developer's guide for PL/Java

### Credits
This guide was developed in collaboration with Navneet Potti (@navsan) and
Nabarun Nag (@nabarunnag). Many thanks to Dave Cramer (@davecramer) and
Daniel Gustafsson (@danielgustafsson) for various suggestions to improve
the original version of this document. Alexey Grishchenko (@0x0FFF) has
also participated in improvement of the document and scripts.

## Who should read this document?
Any one who wants to develop code for GPDB module PL/Java. This guide targets
the free-lance developer who typically has a laptop and wants to develop
GPDB code on it. In other words, such a typical developer does not necessarily
have 24x7 access to a cluster, and needs a miminal stand-alone development
enviroment.

The instructions here were first written and verified on OSX El Capitan,
v.10.11.2. In the future, we hope to add to the list below.

| **OS**        | **Date Tested**    | **Comments**                           |
| :------------ |:-------------------| --------------------------------------:|
| OSX v.10.11.2 | 2015-12-29         | Vagrant v. 1.8.1; VirtualBox v. 5.0.12 |

## 1: Setup VirtualBox and Vagrant
You need to setup both VirtualBox and Vagrant. If you don't have these
installed already, then head over to https://www.virtualbox.org/wiki/Downloads
and http://www.vagrantup.com/downloads to download and then install them.

##2: Clone PL/Java code from github
Go to the directory in your machine where you want to check out the PL/Java
code, and clone the PL/Java code by typing the following into a terminal window.

```shell
git clone https://github.com/greenplum-db/pljava.git
```

##3: Setup and start the virtual machine
Next go to the `pljava/vagrant` directory. This directory has virtual machine
configurations for different operating systems (for now there is only one).
Pick the distro of your choice, and `cd` to that directory. For this document,
we will assume that you pick `centos`. So, issue the following command:

```shell
cd gpdb/vagrant/centos
```

Next let us start a virtual machine using the Vagrant file in that directory.
From the terminal window, issue the following command:

```shell
vagrant up
```

The last command will take a while as Vagrant works with VirtualBox to fetch
a box image for CentOS. The box image is many hundred MiBs is size, so it takes
a while. This image is fetched only once and will be stored by vagrant in a
directory (likely `~/.vagrant.d/boxes/`), so you won't incur this network IO
if you repeat the steps above. A side-effect is that vagrant has now used a
few hundred MiBs of space on your machine. You can see the list of boxes that
vagrant has downloaded using ``vagrant box list``. If you need to drop some
box images, follow the instructions posted [here](https://docs.vagrantup.com/v2/cli/box.html "vagrant manage boxes").

If you are curious about what Vagrant is doing, then open the file
`Vagrantfile`. The `config.vm.box` parameter there specifies the
vagrant box image that is being fetched. Essentially you are creating an
image of CentOS on your machine that will be used below to setup and run GPDB.

While you are viewing the Vagrantfile, a few more things to notice here are:
* The parameter `vb.memory` sets the memory to 8GB for the virtual machine.
  You could dial that number up or down depending on the actual memory in
  your machine.
* The parameter `vb.cpus` sets the number of cores that the virtual machine will
  use to 2. Again, feel free to change this number based on the machine that
  you have.
* Notice the parameter `config.vm.synced_folder`. This configuration requests
  that the code you checked out is mounted as `/pljava` in the virtual machine.
  More on this later below.

Once the command above (`vagrant up`) returns, we are ready to login to the
virtual machine. Type in the following command into the terminal window
(make sure that you are in the directory `pljava/vagrant/centos`):

```shell
vagrant ssh
```

Now you are in the virtual machine shell in a **guest** OS that is running in
your actual machine (the **host**). Everything that you do in the guest machine
will be isolated from the host, except for any changes that you make to
``/pljava`` - recall that we requested that the code we checked out show up at
this mount point in the virtual machine. Thus, if you type ``ls /pljava`` in the
virtual machine shell, then you will see the PL/Java code that you checked out.

That's it - GPDB is built, up and running. You can open database connection right
away with ``psql -d template1`` and start creating your stuff

If you are curious how this happened, take a look at the following scripts:
* `vagrant/centos/vagrant-setup.sh` - this script installs all the packages
  required for GPDB as dependencies and installs OpenJDK 1.8.0 for PL/Java
* `vagrant/centos/vagrant-build.sh` - this script clones GPDB and builds it. In
  case you need to change build options you can change this file and re-create
  VM by running `vagrant destroy` followed by `vagrant up`
* `vagrant/centos/vagrant-configure-os.sh` - this script configures OS
  parameters required for running GPDB
* `vagrant/centos/vagrant-install-inner.sh` - this script is responsible for
  GPDB installation

You can easily go to `vagrant/centos/Vagrantfile` and comment out the calls for
any of these scripts at any time to prevent GPDB installation or OS-level
configurations

Now, you are ready to start GPDB. To do that, type in the following commands
into the (guest) terminal:
```shell
DBNAME=$USER
createdb $DBNAME
psql $DBNAME
```

You should see a psql prompt that says `vagrant=#`. At this point, you can open
up another shell from the host OS. Start another *host* terminal, and go to
the vagrant directory by typing `cd pljava/vagrant`. Then, type in `vagrant ssh`.
From this second guest terminal, you can run GPDB commands like `gpstate`.
Go ahead and try it. You should see a report that states that you have a master
and two segments.

If you want to try out a few SQL commands, go back to the guest shell in which
you have the `psql` prompt, and issue the following SQL commands:

```sql
-- Create and populate a Users table
CREATE TABLE Users (uid INTEGER PRIMARY KEY,
                    name VARCHAR);
INSERT INTO Users
  SELECT generate_series, md5(random())
  FROM generate_series(1, 100000);

-- Create and populate a Messages table
CREATE TABLE Messages (mid INTEGER PRIMARY KEY,
                       uid INTEGER REFERENCES Users(uid),
                       ptime DATE,
                       message VARCHAR);
INSERT INTO Messages
   SELECT generate_series,
          round(random()*100000),
          date(now() - '1 hour'::INTERVAL * round(random()*24*30)),
          md5(random())::text
   FROM generate_series(1, 1000000);

-- Report the number of tuples in each table
SELECT COUNT(*) FROM Messages;
SELECT COUNT(*) FROM Users;

-- Report how many messages were posted on each day
SELECT M.ptime, COUNT(*)
FROM Users U NATURAL JOIN Messages M
GROUP BY M.ptime
ORDER BY M.ptime;
```

You just created a simple warehouse database that simulates users posting
messages on a social media network. The "fact" table (aka. the `Messages`
table) has a million rows. The final query reports the number of messages
that were posted on each day. Pretty cool!

(Note if you want to exit the `psql` shell above, type in `\q`.)
