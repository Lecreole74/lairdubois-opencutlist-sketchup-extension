module Ladb::OpenCutList

  require_relative '../../helper/part_drawing_helper'
  require_relative '../../helper/sanitizer_helper'
  require_relative '../common/common_write_drawing2d_worker'


  class CutlistProcessPartsWorker

    include SanitizerHelper
    include PartDrawingHelper

    def initialize(cutlist,
      part_ids: ,
      processor: ,
      unit: Length::Millimeter
    )

      @cutlist = cutlist

      @part_ids = part_ids
      @processor = processor
      @unit = unit

    end

    # -----

    def run
      return { :errors => [ 'default.error' ] } unless @cutlist
      return { :errors => [ 'tab.cutlist.error.obsolete_cutlist' ] } if @cutlist.obsolete?

      model = Sketchup.active_model
      return { :errors => [ 'tab.cutlist.error.no_model' ] } unless model

      # Retrieve part
      parts = @cutlist.get_real_parts(@part_ids)
      return { :errors => [ 'tab.cutlist.error.unknow_part' ] } if parts.empty?
      # Ask for output dir
      dir = UI.select_directory(title: PLUGIN.get_i18n_string('tab.cutlist.write.title'), directory: '')
      if dir

        folder_names = []
        parts.each do |part|

          # Ignore virtual parts
          next if part.virtual

          group = part.group
          folder_name = group.material_display_name
          folder_name = PLUGIN.get_i18n_string('tab.cutlist.material_undefined') if folder_name.nil? || folder_name.empty?
          folder_name += " - #{group.std_dimension}" unless group.std_dimension.empty?
          folder_name = _sanitize_filename(folder_name)
          folder_path = File.join(dir, folder_name)

          

          file_name = "#{part.number} - #{_sanitize_filename(part.name)}"

          begin

            unless folder_names.include?(folder_name)
              if File.exist?(folder_path)
                if UI.messagebox(PLUGIN.get_i18n_string('core.messagebox.dir_override', { :target => folder_name, :parent => File.basename(dir) }), MB_YESNO) == IDYES
                  FileUtils.remove_dir(folder_path, true)
                else
                  return { :cancelled => true }
                end
              end
              Dir.mkdir(folder_path)
              folder_names << folder_name
            end

            count = 0
            6.times do |i|
              count += 1
              puts "Processing part #{part.number} - #{part.name} (view #{i})..."
              drawing_def = _compute_part_drawing_def(count, part,
                                                      ignore_edges: false,
                                                      origin_position: CommonDrawingDecompositionWorker::ORIGIN_POSITION_DEFAULT
              )

              return { :errors => [ 'tab.cutlist.error.unknow_part' ] } unless drawing_def.is_a?(DrawingDef)

              projection_def = CommonDrawingProjectionWorker.new(drawing_def,
                                                                origin_position: CommonDrawingProjectionWorker::ORIGIN_POSITION_BOUNDS_MIN,
                                                                merge_holes: true,
                                                                merge_holes_overflow: 0.to_l,
                                                                mask: nil,
              ).run
              if projection_def.is_a?(DrawingProjectionDef)
                bounds = projection_def.bounds
                unit_sign, unit_factor = _get_unit_sign_and_factor(@unit)
                unit_transformation = Geom::Transformation.scaling(unit_factor, unit_factor, 1.0)
                origin = Geom::Point3d.new(
                  bounds.min.x,
                  -(bounds.height + bounds.min.y)
                ).transform(unit_transformation)
                size = Geom::Point3d.new(
                  bounds.width,
                  bounds.height
                ).transform(unit_transformation)

                x = _get_value(origin.x)
                y = _get_value(origin.y)
                width = _get_value(size.x)
                height = _get_value(size.y)
                puts "size=(#{width}#{unit_sign} x #{height}#{unit_sign})"
                unless projection_def.layer_defs.empty?

                  _write_projection_def( projection_def,
                                            transformation: unit_transformation,
                                            unit_transformation: unit_transformation,
                                            unit_sign: unit_sign)
                end
              end
              puts "************************************************"
            end
          rescue => e
            puts e.inspect
            puts e.backtrace
            return { :errors => [ [ 'core.error.failed_export_to', { :path => folder_path, :error => e.message } ] ] }
          end
        end

        { :export_path => dir }
      end
    end

    def _get_unit_sign_and_factor(unit)

      require_relative '../../utils/dimension_utils'

      case unit
      when DimensionUtils::INCHES
        unit_factor = 1.0
        unit_sign = 'in'
      when DimensionUtils::CENTIMETER
        unit_factor = 1.0.to_l.to_cm
        unit_sign = 'cm'
      else
        unit_factor = 1.0.to_l.to_mm
        unit_sign = 'mm'
      end

      return unit_sign, unit_factor
    end

    def _get_value(value)
      value.to_f.round(3)
    end

    def _write_projection_def( projection_def,
                                  transformation: IDENTITY,
                                  unit_transformation: IDENTITY,
                                  unit_sign: '')

      require_relative '../../model/drawing/drawing_projection_def'

      return unless projection_def.is_a?(DrawingProjectionDef)

      require_relative '../../utils/transformation_utils'

      flipped = TransformationUtils.flipped?(transformation)
      rot_x, rot_y, rot_z = TransformationUtils.euler_angles(transformation)

      projection_def.layer_defs.sort_by { |v| [ v.type_outer? ? 0 : v.depth, v.type_paths? ? 1 : 0 ] }.each do |layer_def|   # Outer always on back and Path's layers on top of same depth layers

        # id = _svg_get_projection_layer_def_identifier(layer_def, unit_transformation, prefix)

        if layer_def.type_paths?
          puts "type = paths: #{_get_value(Geom::Point3d.new(layer_def.depth, 0).transform(unit_transformation).x)}#{unit_sign}"
          # attributes = {
          #   stroke: _svg_stroke_color_hex(layer_def.has_color? ? layer_def.color : paths_stroke_color),
          #   fill: layer_def.type_closed_paths? ? _svg_fill_color_hex(paths_fill_color) : 'none',
          #   id: id,
          #   'serif:id': id,
          #   'inkscape:label': id
          # }
          # attributes.merge!({ 'shaper:cutDepth': "#{_svg_value(Geom::Point3d.new(layer_def.depth, 0).transform(unit_transformation).x)}#{unit_sign}" }) if layer_def.depth != 0
        elsif layer_def.type_holes? # Keep it before checking outer type
          puts "type = holes: #{_get_value(Geom::Point3d.new(layer_def.depth, 0).transform(unit_transformation).x)}#{unit_sign}"
          # attributes = {
          #   stroke: _svg_stroke_color_hex(holes_stroke_color, holes_fill_color),
          #   fill: _svg_fill_color_hex(holes_fill_color),
          #   id: id,
          #   'serif:id': id,
          #   'inkscape:label': id
          # }
          # attributes.merge!({ 'shaper:cutDepth': "#{_svg_value(Geom::Point3d.new(layer_def.depth, 0).transform(unit_transformation).x)}#{unit_sign}" }) if layer_def.depth > 0
        elsif layer_def.type_outer? || layer_def.depth == 0
          puts "type = outer or depth=0: #{_get_value(Geom::Point3d.new(layer_def.depth, 0).transform(unit_transformation).x)}#{unit_sign}"
          # attributes = {
          #   stroke: _svg_stroke_color_hex(stroke_color, fill_color),
          #   fill: _svg_fill_color_hex(fill_color),
          #   id: id,
          #   'serif:id': id,
          #   'inkscape:label': id
          # }
          # attributes.merge!({ 'shaper:cutDepth': "#{_svg_value(Geom::Point3d.new(layer_def.depth, 0).transform(unit_transformation).x)}#{unit_sign}" }) if layer_def.depth > 0
        else
          puts "type = depths: #{_get_value(Geom::Point3d.new(layer_def.depth, 0).transform(unit_transformation).x)}#{unit_sign}"
          # attributes = {
          #   stroke: if depths_stroke_color
          #             ColorUtils.color_to_hex(depths_stroke_color)
          #           else
          #               _svg_stroke_color_hex(stroke_color, fill_color)
          #           end,
          #   fill: if depths_fill_color
          #           ColorUtils.color_to_hex(depths_fill_color)
          #         else
          #           fill_color ? ColorUtils.color_to_hex(ColorUtils.color_lighten(fill_color, projection_def.max_depth > 0 ? (layer_def.depth / projection_def.max_depth) * 0.6 + 0.2 : 0.3)) : 'none'
          #         end,
          #   id: id,
          #   'serif:id': id,
          #   'inkscape:label': id,
          #   'shaper:cutDepth': "#{_svg_value(Geom::Point3d.new(layer_def.depth, 0).transform(unit_transformation).x)}#{unit_sign}"
          # }
        end

        data = []

        layer_def.poly_defs.each do |poly_def|

          if poly_def.curve_def

            if poly_def.curve_def.circle?

              # Simplify circle drawing by using only xradius

              portion = poly_def.curve_def.portions.first
              center = portion.ellipse_def.center
              radius = portion.ellipse_def.xradius
              position1 = Geom::Point3d.new(
                center.x - radius,
                center.y
              ).transform(transformation)
              position2 = Geom::Point3d.new(
                center.x + radius,
                center.y
              ).transform(transformation)
              radius = Geom::Point3d.new(radius, 0).transform(unit_transformation)
              x1 = _get_value(position1.x)
              y1 = _get_value(-position1.y)
              x2 = _get_value(position2.x)
              y2 = _get_value(-position2.y)
              r = _get_value(radius.x)
              puts "x = #{x1+r}"
              puts "y = #{y1}"
              puts "r = #{r}"

              sflag = portion.ccw? ? 0 : 1

              data << "M #{x1},#{y1} A #{r},#{r} 0 0,#{sflag} #{x2},#{y2} A #{r},#{r} 0 0,#{sflag} #{x1},#{y1} Z"
            else

              # Extract loop points from ordered edges and arc curves
              data << "#{poly_def.curve_def.portions.map.with_index { |portion, index|

                portion_data = []
                start_point = portion.start_point.transform(transformation)
                end_point = portion.end_point.transform(transformation)
                portion_data << "M #{_get_value(start_point.x)},#{_get_value(-start_point.y)}" if index == 0

                if portion.is_a?(Geometrix::ArcCurvePortionDef)

                  radius = Geom::Point3d.new(
                    portion.ellipse_def.xradius,
                    portion.ellipse_def.yradius
                  ).transform(unit_transformation)
                  middle = portion.mid_point.transform(transformation)

                  rx = _get_value(radius.x)
                  ry = _get_value(radius.y)
                  xrot = -portion.ellipse_def.angle.radians.round(3) + rot_z.radians.round(3)
                  lflag = 0
                  sflag = if flipped ? !portion.ccw? : portion.ccw?
                            0
                          else
                            1
                          end
                  x1 = _get_value(middle.x)
                  y1 = _get_value(-middle.y)
                  x2 = _get_value(end_point.x)
                  y2 = _get_value(-end_point.y)

                  portion_data << "A #{rx},#{ry} #{xrot} #{lflag},#{sflag} #{x1},#{y1}"
                  portion_data << "A #{rx},#{ry} #{xrot} #{lflag},#{sflag} #{x2},#{y2}"

                else

                  portion_data << "L #{_get_value(end_point.x)},#{_get_value(-end_point.y)}"

                end

                portion_data
              }.join(' ')} #{poly_def.curve_def.closed? ? 'Z' : ''}"

            end

          else

            # Extract loop points from vertices (quicker)
            data << "M #{poly_def.points.map { |point|
              point = point.transform(transformation)
              point.y *= -1
              "#{_get_value(point.x)},#{_get_value(point.y)}"
            }.join(' L ')}#{poly_def.curve_def.closed? ? 'Z' : ''}"

          end

        end

      end

    end

  end
end
