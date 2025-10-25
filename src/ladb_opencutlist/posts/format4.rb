module Format4Processor
  @name = "Format4"
  @version = "2.0"
  @extension = ".gcode"

  @index = 0

  def self._tcn_get_index
    @index += 1
  end

  def self._execute_process(parts_with_sides)
  # def self._execute_process(parts_with_sides, folder_path)
  
    puts "Processor: #{@name} v#{@version}"
    # puts "Dir: #{folder_path}"

    parts_with_sides.each do |part_with_sides|
      part = part_with_sides[:part]
      material_name = part[:material_name]
      sides = _reorder_sides_for_tpacad(part_with_sides[:sides])
      part_name = part[:name]
      part_number = part[:number]
      length = _tcn_value(part[:length])
      width = _tcn_value(part[:width])
      thickness = _tcn_value(part[:thickness])
      part_count = part[:count]
      entity_names = part[:entity_names][0][0].empty? ? '_' : "-#{part[:entity_names][0][0]}_"
      folder_path = part_with_sides[:folder_path]
      # filename = "#{part_name} - #{part_number} - #{material_name}"
      
      filename = "#{part_name}#{entity_names}#{length}x#{width} (x#{part_count})"
      
      file_path = File.join(folder_path, "#{filename}.#{@extension}")
      # puts "Filename: #{filename} length: #{length}, width: #{width}, thickness: #{thickness}"
      File.open(file_path, "w:ISO-8859-1") do |file|
        _write_tnc_file_start(file, length, width, thickness)
        side_numbers = [1, 3, 4, 5, 6]
        side_numbers.each do |face_number|
          # puts "\nFace #{face_number}"
          _write_side_start(file, face_number)
          _write_works(file, face_number, sides[:"side#{face_number}"], length, width, thickness) if !sides[:"side#{face_number}"].empty?
          _write_side_end(file)
        end
      end
    end
  end

  def self._reorder_sides_for_tpacad(ocl_sides)
  { side1: ocl_sides[:side2], side2: ocl_sides[:side1], side3: ocl_sides[:side6], side4: ocl_sides[:side4], side5: ocl_sides[:side5], side6: ocl_sides[:side3]}
  end

  def self._tcn_value(str)
    str.to_s.gsub(/[~\s]/, '').gsub(',', '.').to_f
  end

  def self._write_side_start(file, face_number)
    file.puts("SIDE##{face_number}{")
    file.puts('::DX=0 XY=1') if face_number != 1
  end

  def self._write_side_end(file)
    file.puts('}SIDE')
  end

  def self._get_infos()
    {:name => @name, :version => @version, :extension => @extension}
  end

  def self._write_tnc_file_start(file, length, width, thickness)
    file.puts('TPA\ALBATROS\EDICAD\02.00:1665:r0w0s1')
    file.puts('::SIDE=0;')
    file.puts('::ATTR=hide;varv')
    file.puts("::UNm DL=#{length} DH=#{width} DS=#{thickness}")
    file.puts("'tcn version=2.9.20")
    file.puts("'code=ansi'")
    file.puts('EXE{')
    file.puts('#0=0')
    file.puts('#1=0')
    file.puts('#2=0')
    file.puts('#3=0')
    file.puts('#4=0')
    file.puts('}EXE')
    file.puts('OFFS{')
    file.puts('#0=0.0|0')
    file.puts('#1=0.0|0')
    file.puts('#2=0.0|0')
    file.puts('}OFFS')
    file.puts('VARV{')
    file.puts('#0=0.0|0')
    file.puts('#1=0.0|0')
    file.puts('}VARV')
    file.puts('VAR{')
    file.puts('}VAR')
    file.puts('SPEC{')
    file.puts('}SPEC')
    file.puts('INFO{')
    file.puts('}INFO')
    file.puts('OPTI{')
    file.puts(':: OPTKIND=%;0 OPTROUTER=%;0 LSTCOD=%0%1%2')
    file.puts('}OPTI')
    file.puts('LINK{')
    file.puts('}LINK')
    file.puts('SIDE#0{')
    file.puts('W#1511{ ::WT2 WF=1  #8098=..\custom\mcr\fresatebarnesting.tmcr }W')
    file.puts('}SIDE')
  end

  def self._write_works(file, face_number, side, length, width, thickness)
    side[:works].each do |work|
      case work[:type]
      when 'HOLE'
        _write_hole(file, face_number, work, length, width, thickness)
      when 'SETUP'
        puts "works :"
        puts work[:works]
        _write_setup(file, face_number, work[:works], length, width, thickness) if face_number == 1 && work[:works][0][:z] != 0
      end
    end
  end

  def self._write_hole(file, face_number, hole, length, width, thickness)
    x, y = _tcn_symetrie_axe_vertical(hole[:cx], hole[:cy], length/2, width/2, face_number)
    z = -hole[:cz]
    d = hole[:rx]*2
    borgne = (face_number != 1 || (z.abs < thickness)) ? "0" : "1"
    index = _tcn_get_index
    file.puts("W#81{ ::WTp WS=#{index}  #8015=0 #1=#{x.round(2)} #2=#{y.round(2)} #3=#{z} #1002=#{d.round(0)} #201=1 #203=1 #1001=#{borgne} #9505=0 }W")
  end

  def self._write_setup(file, face_number, works, length, width, thickness)
    # puts "works :"
    # puts works
    index = 0
    ox = 0
    oy = 0
    oz = 0
    works.each do |work|
      # puts "index: #{index}"
      case work[:type]
      when "L01"
        puts "L01 -> #{work[:z]}"
        x, y = _tcn_symetrie_axe_vertical(work[:x], work[:y], length/2, width/2, face_number)
        x = x.round(0)
        y = y.round(0)
        z = work[:z]
        p1 = [ox, oy]
        p2 = [x,y]
        rlength, rwidth = _get_real_length_and_width_by_side(length, width, thickness, face_number)
        file.puts("W#2201{ ::WTl  #8015=0 #8121=#{ox.round(2)} #8122=#{oy.round(2)} #8123=#{-z} #1=#{x.round(2)} #2=#{y.round(2)} #3= #42=0 #49=0 }W") if index == 1
        file.puts("W#2201{ ::WTl  #8015=0 #1=#{x.round(2)} #2=#{y.round(2)} #3= #42=0 #49=0 }W") if index > 1
        ox, oy, oz = [ x, y, z ]
      when "A01"
        puts "A01 -> #{work[:z]}"
        x, y = _tcn_symetrie_axe_vertical(work[:x2], work[:y2], length/2, width/2, face_number)
        r = work[:rx]
        z = work[:z]
        sFlag = work[:sflag] == 0 ? "1" : "0"
        sFlag = work[:sflag] == 0 ? "0" : "1" if face_number == 4
        file.puts("W#2111{ ::WTa  #8015=0 #8121=#{ox.round(2)} #8122=#{oy.round(2)} #8123=-#{oz} #1=#{x.round(2)} #2=#{y.round(2)} #3=-#{z} #34=#{sFlag} #8017=#{r} #8050=0 #42=0 #49=0 }W") if index == 1
        file.puts("W#2111{ ::WTa  #8015=0 #1=#{x.round(2)} #2=#{y.round(2)} #3=-#{z} #34=#{sFlag} #8017=#{r} #8050=0 #42=0 #49=0 }W") if index > 1
        ox, oy, oz = [ x, y, z ]
      end
      index += 1
    end
  end

  def self._get_real_length_and_width_by_side(length, width, thickness, face_number)
    case face_number
    when 1,2
      return [length, width]
    when 3,5
      return [length, thickness]
    when 4,6
      return [width, thickness]
    end
  end

  def self._tcn_symetrie_axe_vertical(x, y, x_sym, y_sym, face_number)
    x_symetrique = 2 * x_sym - x
    y_symetrique = 2 * y_sym - x
    x_symetrique = y_symetrique if face_number == 4
    y = 2 * y_sym - y if face_number == 1
    ([1,3,4].include?(face_number)) ? [x_symetrique, y] : [x, y]
  end

end