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
      @content_layers = @part["content_layer"]
    end

    def run
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
      return if @sides.nil?
      reorder = (@flipped) ? REORDER_SIDE_FLIPPED : REORDER_SIDES
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
        when "path"
          work["datas"].each_with_index do |point, i|
            next_point = work["datas"][i + 1]
            break unless next_point # stop avant la fin
            xi = (i==0) ? _inv_x(point["x"]) : ""
            yi = (i==0) ? _inv_y(point["y"]) : ""
            zi = (i==0) ? point["z"] : ""
            x = _inv_x(next_point["x"])
            y = _inv_y(next_point["y"])
            z = next_point["z"]
            case next_point["type"]
            when "L01"
              str = getTpaL01(0, _trunc(xi), _trunc(yi), _trunc(zi), _trunc(x), _trunc(y), _trunc(z))
              cleaned = str.gsub(/#\d+=\s*(?=(#|\}|$))/, "")
              file.puts(cleaned)
            when "A11"
              ew = (next_point["sflag"]==0) ? 1 : 0
              u = next_point["rx"]
              str = getTpaA11(0, _trunc(xi), _trunc(yi), _trunc(zi), _trunc(x), _trunc(y), _trunc(z), ew, u)
              cleaned = str.gsub(/#\d+=\s*(?=(#|\}|$))/, "")
              file.puts(cleaned)
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

    def getTpaA11(eg, xi, yi, zi, x, y, z, ew, u)
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
      return "W#2111{ ::WTa  #8015=0 #8121=#{xi} #8122=#{yi} #8123=#{zi} #1=#{x} #2=#{y} #3=#{z} #34=#{ew} #8017=#{u} #8050=0 #42=0 #49=0 }W"
    end

    def getTpaBladex(x, xf, y, z, sl, dn)
      # BLADEX
      # #8020 [X] // x de départ
      # #8517 [XF] // x de terminaion
      # #8021 [Y] // y
      # #8022 [Z] // z
      # #8503 [SL] // largeur rainure
      # #8525 [dn] // correction 0:Arrêt 1:Gauche 2:Droite
      return "W#1050{ ::WT2 WS=1  #8098=..\\custom\\mcr\\lame.tmcr #6=1 #8020=#{x} #8021=#{y} #8022=#{z} #9505=0 #8503=#{sl} #8509=0 #8514=1 #8515=1 #8516=2001 #8517=#{xf} #8525=#{dn} #8526=0 #8527=0 }W"
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

    def _inv_x(value)
      x = value.to_f
      new_x = @width - x
      return new_x
    end

    def _inv_y(value)
      y = value.to_f
      new_y = @height - y
      return new_y
    end

    def _find_diameter(value, tolerance = 0.2)
      # Cherche un outil où |value - diameter| <= tolerance
      tool = DIAMETERS_TOOLS.find do |t|
        (value - t).abs <= tolerance
      end
      # Retourne le tool trouvé ou nil
      tool || value
    end

    def _trunc(value, decimals = 2)
      return if value.nil? || value.to_s.strip.empty?
      factor = 10 ** decimals
      truncated = (value.to_f * factor).floor / factor.to_f
      truncated % 1 == 0 ? truncated.to_i : truncated
    end
  end
end
