##########################################################################
#
# pgAdmin 4 - PostgreSQL Tools
#
# Copyright (C) 2013 - 2026, The pgAdmin Development Team
# This software is released under the PostgreSQL Licence
#
##########################################################################

"""A Tables shortcut directly under each database.

The Object Explorer reaches a table through Schemas > public > Tables. This
module adds a 'Tables' collection as the first child of a database, listing
the tables of the 'public' schema, so the common case is one click away.

It is a shortcut, not a new kind of object: the nodes it yields are ordinary
'table' nodes carrying the oid of the public schema, so the context menu,
properties, DDL, View/Edit Data and everything else attached to a table node
work unchanged.
"""

from flask import render_template
from flask_babel import gettext

from config import PG_DEFAULT_DRIVER
from pgadmin.browser.collection import CollectionNodeModule
from pgadmin.browser.server_groups.servers.databases.schemas.tables import \
    blueprint as table_blueprint
from pgadmin.browser.server_groups.servers.databases.schemas.tables.utils \
    import BaseTableView
from pgadmin.browser.utils import PGChildNodeView
from pgadmin.utils.constants import PGADMIN_NODE
from pgadmin.utils.driver import get_driver
from pgadmin.utils.preferences import Preferences


PUBLIC_SCHEMA = 'public'


class PublicTablesModule(CollectionNodeModule):
    """Yields the 'Tables' collection node shown under a database."""

    # The module needs a type of its own: a blueprint is named
    # 'NODE-<node_type>', so reusing 'table' here would collide with the real
    # Tables module and one would silently displace the other in the Flask
    # app. The collection node it yields still advertises the 'table' type
    # for its children, which is what gives them their behaviour.
    _NODE_TYPE = 'public_tables'
    _COLLECTION_LABEL = gettext("Tables")

    # The node type the children carry, and whose module the browser loads
    # to render them.
    CHILD_NODE_TYPE = 'table'

    # Sorts ahead of the database's other children, which carry the default
    # of 0 and stay in alphabetical order among themselves.
    SORT_PRIORITY = -1

    def __init__(self, *args, **kwargs):
        self.min_ver = None
        self.max_ver = None
        super().__init__(*args, **kwargs)

    def get_nodes(self, gid, sid, did):
        """Generate the collection node, if public exists and has tables."""
        # Hidden along with the real Tables node: the shortcut shows the same
        # objects, so 'Show/Hide' for tables has to govern both.
        if not table_blueprint.show_node:
            return

        scid = get_public_schema_oid(sid, did)
        if scid is None:
            return

        # Respect 'Show empty collection nodes?' exactly as the regular
        # Tables collection does, rather than showing an empty shortcut.
        if not self.has_nodes(
            sid, did, scid=scid,
            base_template_path=BaseTableView.BASE_TEMPLATE_PATH
        ):
            return

        # Built by hand rather than through
        # generate_browser_collection_node(): every field has to describe the
        # 'table' node type, so the collection behaves exactly like the one
        # under Schemas and its children are ordinary table nodes. Only the
        # module's own blueprint name differs.
        yield {
            'id': 'coll-%s_%d_public' % (self.CHILD_NODE_TYPE, scid),
            'label': self.collection_label,
            'icon': 'icon-coll-%s' % self.CHILD_NODE_TYPE,
            'inode': True,
            '_type': 'coll-%s' % self.CHILD_NODE_TYPE,
            '_id': scid,
            '_pid': did,
            'module': PGADMIN_NODE % self.CHILD_NODE_TYPE,
            'nodes': [self.CHILD_NODE_TYPE],
            'sort_priority': self.SORT_PRIORITY,
            # The tree builds a node's children URL by walking up to its
            # parents, which here would stop at the database and yield
            # 'table/nodes/<gid>/<sid>/<did>/' - one component short of the
            # scid that endpoint takes. State the path explicitly instead.
            'url_path': '%d/%d/%d/%d' % (gid, sid, did, scid),
            # For the same reason, getTreeNodeHierarchy() would never find
            # a schema above a table listed here, leaving every URL and
            # dialog built from that hierarchy short of one. Supply the
            # schema this shortcut stands for.
            'implied_parents': {
                'schema': {
                    '_type': 'schema',
                    '_id': scid,
                    '_label': PUBLIC_SCHEMA,
                    'label': PUBLIC_SCHEMA,
                },
            },
        }

    @property
    def script_load(self):
        """Load the module script when a database node is initialized."""
        from pgadmin.browser.server_groups.servers import databases
        return databases.DatabaseModule.node_type

    @property
    def csssnippets(self):
        """The table node's CSS is already contributed by the Tables module
        under Schemas, so there is nothing to add here."""
        return []

    @property
    def module_use_template_javascript(self):
        return False

    def register_preferences(self):
        """Pick up the browser preferences the base class exposes.

        Everything the base implementation does is needed - has_nodes()
        reads pref_show_empty_coll_nodes, show_system_objects reads
        pref_show_system_objects - except registering a 'show_node_table'
        preference, which the real Tables module already owns. Registering
        a second one under that name would give the same setting two
        entries in the Nodes preference list.
        """
        self.browser_preference = Preferences.module('browser')
        self.pref_show_system_objects = self.browser_preference.preference(
            'show_system_objects'
        )
        self.pref_show_user_defined_templates = \
            self.browser_preference.preference('show_user_defined_templates')
        self.pref_show_empty_coll_nodes = self.browser_preference.preference(
            'show_empty_coll_nodes'
        )
        # Deliberately not registered; the shortcut follows the real table
        # node's visibility instead, which get_nodes() consults directly.
        self.pref_show_node = None


def get_public_schema_oid(sid, did):
    """Return the oid of the 'public' schema, or None.

    None covers every case where the shortcut should simply not appear: no
    public schema, no rights to it, or a connection that is not usable.
    """
    try:
        manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(sid)
        conn = manager.connection(did=did)
        # Not 'if not conn.connected(): return None'. By the time the tree
        # asks a database for its children the connection often has not
        # been established yet, and bailing out here silently dropped the
        # shortcut. Connect on demand, exactly as the rest of the browser
        # does, and let a genuine failure fall through to the except below.
        if not conn.connected():
            status, msg = conn.connect()
            if not status:
                return None

        status, res = conn.execute_dict(render_template(
            "public_tables/sql/public_schema_oid.sql", conn=conn
        ))
        if not status or not res['rows']:
            return None
        return res['rows'][0]['oid']
    except Exception:
        # A failure here must not break the database node's children; the
        # regular Schemas tree remains available either way.
        return None


blueprint = PublicTablesModule(__name__)


class PublicTablesView(PGChildNodeView):
    """Present only so the module has a blueprint to register.

    The nodes this module yields are plain 'table' nodes, which the browser
    routes to the Tables module's own view; no endpoint of this module is
    ever called for them.
    """

    node_type = blueprint.node_type

    parent_ids = [
        {'type': 'int', 'id': 'gid'},
        {'type': 'int', 'id': 'sid'},
        {'type': 'int', 'id': 'did'},
    ]
    ids = []

    operations = dict({})


PublicTablesView.register_node_view(blueprint)
