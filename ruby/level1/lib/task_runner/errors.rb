module TaskRunner
  class Error < StandardError; end
  class ParseError < Error; end
  class UnknownTargetError < Error; end
  class CircularDependencyError < Error; end
  class CommandError < Error; end
end
