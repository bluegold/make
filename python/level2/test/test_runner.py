import unittest
import os
import sys

# Add src directory to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'src')))
from main import TaskRunner

class TestTaskRunner(unittest.TestCase):
    def setUp(self):
        self.runner = TaskRunner()

    def test_variable_expansion(self):
        self.runner.variables['VAR'] = 'value'
        result = self.runner.expand_variables('The $(VAR)')
        self.assertEqual(result, 'The value')

    def test_late_binding(self):
        # A depends on B, but B is defined later
        self.runner.variables['A'] = '$(B)'
        self.runner.variables['B'] = 'late'
        result = self.runner.expand_variables('A is $(A)')
        self.assertEqual(result, 'A is late')

    def test_dependency_variable_splitting(self):
        # Test that variables in dependencies are split by spaces
        from main import Task
        self.runner.variables['DEPS'] = 'main.o utils.o'
        self.runner.tasks['app'] = Task('app', ['$(DEPS)', 'extra.o'])
        
        self.runner.finalize_parsing()
        
        # 'app' should have 3 dependencies: 'main.o', 'utils.o', 'extra.o'
        deps = self.runner.tasks['app'].dependencies
        self.assertEqual(deps, ['main.o', 'utils.o', 'extra.o'])

if __name__ == '__main__':
    unittest.main()
