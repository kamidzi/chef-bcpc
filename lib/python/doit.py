#!/usr/bin/env python

from bcpc.openstack import credentials
from keystoneclient.auth.identity import v2
from keystoneclient import session
from keystoneclient.v2_0 import client as ksclient
from novaclient.v2 import client as nclient
from time import sleep
import sys


def load_bash_env_file(filename):
    """This ill-advised method will load a bash environment file and process
    it as if where interpreted by the shell. In actual fact, that is all
    that it does: launches a shell with an empty environment then loads the
    file and enumerates the the new environment"""
    # This is silly, because it implies that you would first have to detect the
    # filetype... use shebang maybe?
    from subprocess import check_output
    envvars = check_output(['/usr/bin/env', '-', 'BASH_ENV=%s' % filename,
                            '/bin/bash', '-c', '/usr/bin/env'])
    envmap = {}
    for line in envvars.split('\n'):
        if len(line) == 0:
            continue
        k, v = line.split('=')
        envmap[k] = v
    return envmap


def create_project(ks=None, **project_info):
    if ks is None:
        return None
    return ks.projects.create(**project_info)


def create_tenant(ks=None, **tenant_info):
    if ks is None:
        return None
    return ks.tenants.create(**tenant_info)


def create_user(ks=None, **user_info):
    if ks is None:
        return None
    return ks.users.create(**user_info)


# TODO: Use sessions. See:
# http://docs.openstack.org/developer/python-keystoneclient/using-sessions.html
if __name__ == '__main__':
    import os
    import pprint
    pp = pprint.PrettyPrinter(indent=2)

    env = load_bash_env_file(os.sep.join([os.environ['HOME'], 'adminrc']))
    os.environ.update(env)

    creds = credentials.get_keystone_creds()
    pp.pprint(creds)
    auth = v2.Password(**creds)
    sess = session.Session(auth=auth)
    ks = ksclient.Client(session=sess)

    # Create the tenant
    project_info = {u'tenant_name': u'my-project',
                    u'description': '',
                    u'enabled': True}

    # project = create_project(ks, **project_info)
    project = create_tenant(ks, **project_info)
    pp.pprint(project._info)

    # Create the user, role, and associate
    user_info = {u'name': u'someuser',
                 u'password': u'foobar',
                 u'tenant_id': unicode(project.id),
                 u'email': u'someuser@email.com',
                 u'enabled': True}

    user = create_user(ks, **user_info)

    # Switch to new creds
    # Authenticate as the new user and launch instance
    os.environ['OS_TENANT_NAME'] = project.name
    os.environ['OS_USERNAME'] = user.name
    os.environ['OS_PASSWORD'] = user_info['password']
    creds = credentials.get_nova_creds()

    nc = nclient.Client(**creds)

    params = {u'minDisk': 0, u'minRam': 0}
    img = nc.images.find(**params)
    flavor = nc.flavors.find(name=u'm1.tiny')
    instance_params = {u'name': u'test',
                       u'image': img,
                       u'flavor': flavor}
    instance = nc.servers.create(**instance_params)

    status = instance.status
    while status == 'BUILD':
        sleep(5)
        instance = nc.servers.get(instance.id)
        status = instance.status
    if status != 'ACTIVE':
        print>>sys.stderr, 'Something went wrong. [instance=%s]' % instance.id
        sys.exit(-1)
    pp.pprint(instance._info)

    # Now delete the tenant
    # N.B. - This uses original admin creds
    ks.tenants.delete(project.id)
