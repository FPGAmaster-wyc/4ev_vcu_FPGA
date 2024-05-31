set projName ia2610-system
set part xczu4ev-sfvc784-2-i
set top soc_wrapper

proc run_create {} {
    global projName
    global part
    global top

    set outputDir ./$projName

    file mkdir $outputDir

    create_project $projName $outputDir -part $part -force

    set projDir [get_property directory [current_project]]

    add_files -fileset [current_fileset] -force -norecurse {
        ../src/axi_lite_to_mm.v
        ../src/bitslip.v
        ../src/clock_generation.v
        ../src/column_level_correction.v
        ../src/fifo_async.v
        ../src/fifo_sync.v
        ../src/gvsp_image.v
        ../src/image_dma.v
        ../src/image_processor.v
        ../src/image_stream.v
        ../src/indirect_access.v
        ../src/linear_transform.v
        ../src/lookup_table.v
        ../src/lvds_rx_lane.v
        ../src/lvds_rx_top.v
        ../src/precise_timing.v
        ../src/python_decode.v
        ../src/python_if.v
        ../src/python_clk.v
        ../src/regfile.v
        ../src/spi_ctl.v
        ../src/drv8835_if.v
        ../src/target_packet.v
        ../src/timing_controller.v
        ../src/ia2610_top.v
		../src/soc_wrapper.v
		
		
    }

    add_files -fileset [current_fileset] -force -norecurse {
        ../ip/ila_144/ila_144.xci
        ../ip/vio_0/vio_0.xci
        ../ip/python_if_vio/python_if_vio.xci
    }

    add_files -fileset [current_fileset -constrset] -force -norecurse {
        ../src/ia2610_system.xdc
    }

    source {../bd/soc.tcl}

    set_property top $top [current_fileset]
    set_property generic DEBUG=TRUE [current_fileset]

    set_property AUTO_INCREMENTAL_CHECKPOINT 1 [current_run -implementation]

    update_compile_order
}

proc run_build {} {
    upgrade_ip [get_ips]

    # Synthesis
    launch_runs -jobs 4 [current_run -synthesis]
    wait_on_run [current_run -synthesis]

    # Implementation
    launch_runs -jobs 4 [current_run -implementation] -to_step write_bitstream
    wait_on_run [current_run -implementation]
}

proc run_dist {} {
    global projName
    global top

    # Copy binary files
    set prefix [get_property DIRECTORY [current_run -implementation]]
    #set bit_fn [format "%s/%s.bit" $prefix $top]
    #set dbg_fn [format "%s/debug_nets.ltx" $prefix]
    #file copy -force $bit_fn {./}
    #file copy -force $dbg_fn {./}

    # Export hardware
    # Before 2019.2
    #set sdk_path [format "%s/%s.sdk" $projName $projName]
    #set hdf_fn [format "%s/%s.hdf" $sdk_path $top]
    # Export with bitstream
    #set sysdef_fn [format "%s/%s.sysdef" $prefix $top]
    #file copy -force $sysdef_fn $hdf_fn
    # Export without bitstream
    #file mkdir $sdk_path
    #write_hwdef -force -file $hdf_fn
    # Post 2019.2
    set xsa_fn [format "%s.xsa" $projName]
    write_hw_platform -fixed -force -file $xsa_fn

    # Archieve project
    set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    archive_project -force [format "%s_%s.xpr" [current_project] $timestamp]
}

