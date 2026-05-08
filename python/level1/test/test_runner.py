import unittest
import os
import sys

# Add src directory to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'src')))
from main import TaskRunner

class TestTaskRunner(unittest.TestCase):
    def setUp(self):
        self.runner = TaskRunner()

    def test_dependency_order(self):
        # Manually inject tasks
        from main import Task
        self.runner.tasks['all'] = Task('all', ['b', 'a'])
        self.runner.tasks['a'] = Task('a', [])
        self.runner.tasks['b'] = Task('b', ['a'])
        
        order = self.runner.resolve_dependencies('all')
        # Topological sort: a should come before b, b should come before all
        self.assertEqual(order, ['a', 'b', 'all'])

    def test_circular_dependency(self):
        from main import Task
        self.runner.tasks['a'] = Task('a', ['b'])
        self.runner.tasks['b'] = Task('b', ['a'])
        
        with self.assertRaises(SystemExit):
            self.runner.resolve_dependencies('a')

if __name__ == '__main__':
    unittest.main()
