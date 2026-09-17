##########################################################################
#
# pgAdmin 4 - PostgreSQL Tools
#
# Copyright (C) 2013 - 2026, The pgAdmin Development Team
# This software is released under the PostgreSQL Licence
#
##########################################################################

"""Tests the ordering of a node's children in the Object Explorer.

Children are sorted by label, and any node carrying a 'sort_priority' is
then moved ahead of that run. The Tables shortcut under a database relies
on this to stay first.
"""

import json

from pgadmin.browser.utils import NodeView
from pgadmin.utils.route import BaseTestGenerator


class ChildrenSortPriorityTestCase(BaseTestGenerator):
    """Verifies sort_priority ordering in NodeView.children()."""

    scenarios = [
        ('Children without a priority stay alphabetical', dict(
            children=[
                {'label': 'Schemas'},
                {'label': 'Casts'},
                {'label': 'Extensions'},
            ],
            expected=['Casts', 'Extensions', 'Schemas'],
        )),
        ('A negative priority sorts ahead of everything else', dict(
            children=[
                {'label': 'Casts', 'sort_priority': 0},
                {'label': 'Schemas', 'sort_priority': 0},
                {'label': 'Tables', 'sort_priority': -1},
            ],
            expected=['Tables', 'Casts', 'Schemas'],
        )),
        ('A missing priority is treated as zero', dict(
            children=[
                {'label': 'Casts'},
                {'label': 'Tables', 'sort_priority': -1},
                {'label': 'Aardvark'},
            ],
            expected=['Tables', 'Aardvark', 'Casts'],
        )),
        ('Equal priorities keep the order they were given', dict(
            children=[
                {'label': 'Beta', 'sort_priority': -1},
                {'label': 'Alpha', 'sort_priority': -1},
            ],
            expected=['Alpha', 'Beta'],
        )),
        # The reported bug: Tables came last, in its alphabetical place.
        ('Tables leads a real database\'s children', dict(
            children=[
                {'label': 'Casts'},
                {'label': 'Catalogs'},
                {'label': 'Event Triggers'},
                {'label': 'Extensions'},
                {'label': 'Foreign Data Wrappers'},
                {'label': 'Languages'},
                {'label': 'Publications'},
                {'label': 'Schemas'},
                {'label': 'Subscriptions'},
                {'label': 'Tables', 'sort_priority': -1},
            ],
            expected=[
                'Tables', 'Casts', 'Catalogs', 'Event Triggers',
                'Extensions', 'Foreign Data Wrappers', 'Languages',
                'Publications', 'Schemas', 'Subscriptions',
            ],
        )),
    ]

    def runTest(self):
        view = NodeView.__new__(NodeView)
        view.get_children_nodes = lambda *a, **kw: self.children

        with self.app.test_request_context():
            response = view.children()

        labels = [
            node['label'] for node in json.loads(response.data)['data']
        ]
        self.assertEqual(labels, self.expected)
