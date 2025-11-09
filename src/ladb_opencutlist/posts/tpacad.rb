module Ladb::OpenCutList
  class CutlistProcessPartWorker   # <= ici module → class
    PROCESSOR_NAME = "Tpacad"
    PROCESSOR_VERSION = "1.0.0"
    PROCESSOR_EXTENSION = "tcn"

    DIAMETERS_TOOLS = [2, 5, 8, 35]
    REORDER_SIDES = [nil, "PART_DRAWING_TYPE_2D_BOTTOM", nil, "PART_DRAWING_TYPE_2D_BACK", "PART_DRAWING_TYPE_2D_RIGHT","PART_DRAWING_TYPE_2D_FRONT" , "PART_DRAWING_TYPE_2D_LEFT"]
    REORDER_SIDE_FLIPPED = [nil, "PART_DRAWING_TYPE_2D_BOTTOM", nil, "PART_DRAWING_TYPE_2D_BACK", "PART_DRAWING_TYPE_2D_LEFT", "PART_DRAWING_TYPE_2D_FRONT", "PART_DRAWING_TYPE_2D_RIGHT"]

    def initialize(part: nil)
      @part = part
      @width = _trunc(@part["size"]["width"])
      @height = _trunc(@part["size"]["height"])
      @thickness = _trunc(@part["size"]["thickness"])
      @number = @part["number"]
      @name = @part["name"]
      @count = @part["count"]
      @folder_path = @part["folder_path"]
      @sides = @part["faces"]
      @flipped = @part["flipped"]
    end

    def run
      puts "Processing part #{@part["id"]} with #{PROCESSOR_NAME} v#{PROCESSOR_VERSION}"
      filename = "#{@number}_#{@name}_#{@width}x#{@height} (x#{@count})"
      file_path = File.join(@folder_path, "#{filename}.#{PROCESSOR_EXTENSION}")
      File.open(file_path, "w:ISO-8859-1") do |file|
        _writeHeader(file)
        _process_sides(file)
      end
    end

    def _writeHeader(file)
      file.puts('TPA\ALBATROS\EDICAD\02.00:1666:r0w0s1')
      file.puts("::SIDE=0;")
      file.puts("::ATTR=hide;varv")
      file.puts("::UNm DL=#{@width} DH=#{@height} DS=#{@thickness}")
      file.puts("'tcn version=2.9.20")
      file.puts("'code=unicode")
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
    end

    def _process_sides(file)
      puts "Processing sides..."
      return if @sides.nil?
      if @flipped
        puts "flipped=true"
        reorder = REORDER_SIDE_FLIPPED 
      else
        puts "flipped=false"
        reorder = REORDER_SIDES
      end
      reorder.each_with_index do |side, index|
        next if side.nil?
        next unless @sides.key?(side)
        _writeToolToSide(file, @sides[side], index)
      end
    end

    def _writeToolToSide(file, side, side_number)
      if side_number==3 || side_number==4
        side = _invert_positionx(side)
      end
      if side_number==1
        side = _invert_positionx(side)
        side = _invert_positiony(side)
      end
      file.puts("SIDE##{side_number}{")
      if side_number==1
        file.puts('$=Up') 
      else
        file.puts('::DX=0 XY=1')
      end
      side["works"].each do |work|
        type = work["type"]
        case type
        when "hole"
          thickness = _trunc(side["size"]["thickness"])
          x = _trunc(work["x"])
          y = _trunc(work["y"])
          z = _trunc(work["z"])
          td = _find_diameter(_trunc(work["d"]))
          tp = (thickness+z<=0) ? 1 : 0
          str = getTpaHole( 0, x, y, z, td, tp ) 
          file.puts(str)
        when "setup"
          work["datas"].each_with_index do |point, i|
            next_point = work["datas"][i + 1]
            break unless next_point # stop avant la fin
            xi = (i==0) ? point["x"] : ""
            yi = (i==0) ? point["y"] : ""
            zi = (i==0) ? point["z"] : ""
            x = (i==0) ? next_point["x"] : next_point["x"]
            y = (i==0) ? next_point["y"] : next_point["y"]
            z = (i==0) ?  next_point["z"] : next_point["z"]
            case next_point["type"]
            when "L01"
              str = getTpaL01(0, _trunc(xi), _trunc(yi), _trunc(zi), _trunc(x), _trunc(y), _trunc(z))
              file.puts(str)
            when "A01"
              puts point
              ew = (next_point["sflag"]==0) ? 1 : 0
              i = (next_point["x"]-point["x"])/2
              j = (next_point["y"]-point["y"])/2
              puts "ew:#{ew} i:#{i} j:#{j}"
              str = getTpaA01(0, _trunc(xi), _trunc(yi), _trunc(zi), _trunc(x), _trunc(y), _trunc(z), ew, i, j)
              file.puts(str)
            end
          end
        end
      end
      file.puts("}SIDE")
    end

    def getTpaHole(eg, x, y, z, td, tp)
      # HOLE
      # #8015 [EG] // 0:Absolute 1:Relatif
      # #1 [X] // x
      # #2 [Y] // y
      # #3 [Z] // z
      # #1001 [TP] // typologie 0:borgne 1:passant
      # #1002 [TD] // diamétre
      return "W#81{ ::WTp  #8015=#{eg} #1=#{x} #2=#{y} #3=#{z} #1002=#{td} #201=1 #203=1 #1001=#{tp} #9505=0 }W"
    end

    def getTpaL01(eg, xi, yi, zi, x, y, z)
      # L01
      # #8015 [EG] // 0:Absolute 1:Relatif
      # #8121 [XI] // x départ
      # #8122 [YI] // y départ
      # #8123 [ZI] // z départ
      # #1 [X] // x terminaison
      # #2 [Y] // y terminaison
      # #3 [Z] // z terminaison
      return "W#2201{ ::WTl  #8015=#{eg} #8121=#{xi} #8122=#{yi} #8123=#{zi} #1=#{x} #2=#{y} #3=#{z} #42=0 #49=0 }W"
    end

    def getTpaA01(eg, xi, yi, zi, x, y, z, ew, i, j)
      # A01
      # #8015 [EG] // 0:Absolute 1:Relatif
      # #8121 [XI] // x départ
      # #8122 [YI] // y départ
      # #8123 [ZI] // z départ
      # #1 [X] // x terminaison
      # #2 [Y] // y terminaison
      # #3 [Z] // z terminaison
      # #34 [EW] // 0:sens aiguille 1:sens inverse
      # #31 [I] // centre x
      # #32 [J] // centre y
      return "W#2101{ ::WTa  #8015=#{eg} #8121=#{xi} #8122=#{yi} #8123=#{zi} #1=#{x} #2=#{y} #3=#{z} #34=#{ew} #31=#{i} #32=#{j} #42=0 #49=0 }W"
    end

    #Utilitaires
    def _invert_positionx(side)
      width = side["size"]["width"]
      side["works"].each do |work|
        x = work["x"].to_f
        new_x = width - x
        work["x"] = new_x
      end 
      return side
    end

    def _invert_positiony(side)
      height = side["size"]["height"]
      side["works"].each do |work|
        y = work["y"].to_f
        new_y = height - y
        work["y"] = new_y
      end
      return side
    end

    def _find_diameter(value, tolerance = 0.2)
      # Cherche un outil où |value - diameter| <= tolerance
      tool = DIAMETERS_TOOLS.find do |t|
        (value - t).abs <= tolerance
      end
      # Retourne le tool trouvé ou nil
      tool || v
    end

    def _trunc(value, decimals = 2)
      return if value.nil? || value.to_s.strip.empty?
      factor = 10 ** decimals
      truncated = (value.to_f * factor).floor / factor.to_f
      truncated % 1 == 0 ? truncated.to_i : truncated
    end

  end
end
