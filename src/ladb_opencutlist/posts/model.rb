module Ladb::OpenCutList
  class CutlistProcessPartWorker   # <= ici module → class
    PROCESSOR_NAME = "Model"
    PROCESSOR_VERSION = "1.0.0"
    PROCESSOR_EXTENSION = "ext"

    def initialize(part: nil)
      @part = part
    end

    def run

    end
  end
end