import unittest
from unittest import mock
import os
import sys
from io import StringIO

# Add src directory to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'src')))
from main import TaskRunner

class TestTaskRunner(unittest.TestCase):
    def setUp(self):
        self.runner = TaskRunner()

    def test_basic_expansion(self):
        self.runner.variables['NAME'] = 'world'
        result = self.runner.expand_variables('Hello, $(NAME)!')
        self.assertEqual(result, 'Hello, world!')

    def test_recursive_expansion(self):
        self.runner.variables['A'] = '$(B)'
        self.runner.variables['B'] = 'final'
        result = self.runner.expand_variables('Value is $(A)')
        self.assertEqual(result, 'Value is final')

    def test_automatic_variables(self):
        extra = {
            '$@': 'target.txt',
            '$<': 'input.txt',
            '$^': 'input.txt dep2.txt'
        }
        result = self.runner.expand_variables('Building $@ from $< (all: $^)', extra_vars=extra)
        self.assertEqual(result, 'Building target.txt from input.txt (all: input.txt dep2.txt)')

    def test_circular_reference(self):
        self.runner.variables['A'] = '$(B)'
        self.runner.variables['B'] = '$(A)'
        # Using a context manager to catch sys.exit(1)
        with self.assertRaises(SystemExit):
            # Suppress print output during test
            with StringIO() as buf, unittest.mock.patch('sys.stdout', buf):
                self.runner.expand_variables('$(A)')

    def test_environment_fallback(self):
        os.environ['TEST_ENV_VAR'] = 'env_value'
        result = self.runner.expand_variables('Env: $(TEST_ENV_VAR)')
        self.assertEqual(result, 'Env: env_value')
        del os.environ['TEST_ENV_VAR']

    def test_undefined_variable(self):
        # Undefined variables should expand to empty string
        result = self.runner.expand_variables('Val: $(UNDEFINED)')
        self.assertEqual(result, 'Val: ')

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
