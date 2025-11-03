module Ladb::OpenCutList
  class CutlistProcessPartWorker   # <= ici module → class
    PROCESSOR_NAME = "Tpacad"
    PROCESSOR_VERSION = "1.0.0"
    PROCESSOR_EXTENSION = "tcn"
    def initialize(part: nil)
      @part = part
    end

    def run

      puts "Processing part #{@part["id"]} with #{PROCESSOR_NAME} v#{PROCESSOR_VERSION}"
      size = @part["size"]
      width = size["width"]
      height = size["height"]
      thickness = size["thickness"]
      folder_path = @part["folder_path"]
      filename = "#{@part["name"]}_#{width}x#{height} (x#{@part["count"]})"
      file_path = File.join(folder_path, "#{filename}.#{PROCESSOR_EXTENSION}")
      puts "Filename: #{filename} width: #{width}, height: #{height}, thickness: #{thickness}"
      puts "File path: #{file_path}"
      File.open(file_path, "w:ISO-8859-1") do |file|
        _write(file, width, height, thickness)
      end

    end
    def _write(file, width, height, thickness)
      file.puts('TPA\ALBATROS\EDICAD\02.00:1666:r0w0s1')
      file.puts("::SIDE=0;")
      file.puts("::ATTR=hide;varv")
      file.puts("::UNm DL=#{width} DH=#{height} DS=#{thickness}")
      file.puts("'tcn version=2.9.20'")
      file.puts("'code=unicode'")
      file.puts("EXE{")
      file.puts("#0=0")
      file.puts("#1=0")
      file.puts("#2=0")
      file.puts("#3=0")
      file.puts("#4=0")
      file.puts("}EXE")
      file.puts("OFFS{")
      file.puts("#0=0.0|0")
      file.puts("#1=0.0|0")
      file.puts("#2=0.0|0")
      file.puts("}OFFS")
      file.puts("VARV{")
      file.puts("#0=0.0|0")
      file.puts("#1=0.0|0")
      file.puts("}VARV")
      file.puts("VAR{")
      file.puts("}VAR")
      file.puts("SPEC{")
      file.puts("}SPEC")
      file.puts("INFO{")
      file.puts("}INFO")
      file.puts("OPTI{")
      file.puts(":: OPTKIND=%;0 OPTROUTER=%;0 LSTCOD=%0%1%2")
      file.puts("}OPTI")
      file.puts("LINK{")
      file.puts("}LINK")
      file.puts("SIDE#0{")
      file.puts('W#1511{ ::WT2 WF=1  #8098=..\custom\mcr\fresatebarnesting.tmcr }W')
      file.puts("}SIDE")
      file.puts("SIDE#1{")
      file.puts("$=Up")
      file.puts("}SIDE")
      file.puts("SIDE#3{")
      file.puts("::DX=0 XY=1")
      file.puts("}SIDE")
      file.puts("SIDE#4{")
      file.puts("::DX=0 XY=1")
      file.puts("}SIDE")
      file.puts("SIDE#5{")
      file.puts("::DX=0 XY=1")
      file.puts("}SIDE")
      file.puts("SIDE#6{")
      file.puts("::DX=0 XY=1")
      file.puts("}SIDE")
    end
  end
end
