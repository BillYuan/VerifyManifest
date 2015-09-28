#********************************************************************************************
# Copyright (c) 2013 - 2015, Freescale Semiconductor, Inc.
# All rights reserved.
# #
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
# #
# o Redistributions of source code must retain the above copyright notice, this list
#   of conditions and the following disclaimer.
# #
# o Redistributions in binary form must reproduce the above copyright notice, this
#   list of conditions and the following disclaimer in the documentation and/or
#   other materials provided with the distribution.
# #
# o Neither the name of Freescale Semiconductor, Inc. nor the names of its
#   contributors may be used to endorse or promote products derived from this
#   software without specific prior written permission.
# #
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# Description: Use to auto verify the ksdk_manifest.xml file, check the devices,
# part number supporting list.
# Note that, it supports the KSDK 1.2.0 GA or higher.
#
# Revision History:
# -----------------
# Code Version    YYYY-MM-DD    Author        Description
# 0.1             2015-09-12    Bill Yuan     Create this file

require 'rubygems'
require 'optparse'
require 'nokogiri'
require 'find'
require 'fileutils'
require 'json'
require "awesome_print"
require 'yaml'
require 'win32ole'

DEBUG = false

#derived part number excel from PRD
SHEET_NAME = "Part_Number_Support"
CPU_NAME_CLOUMN = 'C'
CPU_NAME_ROW_START = 2
CPU_NAME_ROW_END = 38

class SDKSource
  attr_reader :sdk_path, :board_list, :device_list, :derived_parts_list, :driver_list, :hal_list
  public
    def initialize(path)
      @sdk_path = path
      @board_list = get_folder_list(@sdk_path + "/examples")
      @device_list = get_folder_list(@sdk_path + "/platform/devices")

      #driver list include the system service and the osa
      @driver_list = get_folder_list(@sdk_path + "/platform/drivers/src") + get_folder_list(@sdk_path + "/platform/system/src")
      @driver_list.push("os_abstraction")

      @hal_list = get_folder_list(@sdk_path + "/platform/hal/src")
      @derived_parts_list = parser_registers_file()
    end

    def get_board_list()
      return @board_list
    end

    def get_device_list()
      return @device_list
    end

    def get_derived_parts_list()
      return @derived_parts_list
    end

    def get_driver_list()
      return @driver_list
    end

    def get_hal_list()
      return @hal_list
    end

  private
    def get_folder_list(folder)
      if !File.exist?(folder)
        puts "folder does not exist: " + folder
        exit(1)
      end

      list = Array.new()
      Dir.foreach(folder) do |item|
        if File.directory?(File.expand_path(item, folder)) and !list.include?(item) and item != "." and item != ".."
         list.push(item) if !list.include?(item)
        end
      end

      if DEBUG
        puts "\nget folder list in: " + folder
        puts list
      end

      return list
    end

    def parser_registers_file()
      registers_file = @sdk_path + "/platform/devices/fsl_device_registers.h"
      if !File.exist?(registers_file)
        puts "registers_file does not exist: " + registers_file
        exit(1)
      end

      cpu_list = Array.new()
      content = File.readlines(registers_file)
      search_list = content.to_s.scan(/CPU_.+?\s*\)/)
      search_list.each do |item|
        cpu_name = item.gsub(/\)/, "").gsub(/CPU_/, "") #remove CPU_ and ) at the end
        cpu_list.push(cpu_name) if !cpu_list.include?(cpu_name)
      end

      print cpu_list if DEBUG

      return cpu_list
    end
end

class ManifestInfo
  attr_reader :sdk_path, :manifest_xml
  public
    def initialize(path)
      @sdk_path = path

      file = File.open(@sdk_path + "/ksdk_manifest.xml")
      @manifest_xml = Nokogiri::XML(file)
    end

    def get_board_list()
      return get_name_list("/boards/board", nil)
    end

    def get_device_list()
      return get_name_list("/devices/device", nil)
    end

    def get_derived_parts_list()
      return get_name_list("/devices/device/package", nil)
    end

    def get_driver_list()
      list = get_component_name_list("/components/component", "driver")

      #exception, flash is defined in other component
      other_list = get_name_list("/components/component", "other")
      if other_list.include?("flash")
        list.push("flash")
      end

      return list
    end

    def get_hal_list()
      return get_component_name_list("/components/component", "hal")
    end

    def get_driver_components()
      return get_componets("driver")
    end

    def get_hal_components()
      return get_componets("hal")
    end

    def get_other_components()
      return get_componets("other")
    end

  private

    def get_name_list(css_key, type)
      list = Array.new()
      @manifest_xml.children.each do |parent|
        parent.css(css_key).each do |item|
          if type != nil and type != item.attr('type')
            next
          end
          name = item.attr('name')
          list.push(name) if !list.include?(name)
        end
      end

      if DEBUG
        if type
          puts "\nget_name from xml, css_key: " + css_key + " type: " + type
        else
          puts "\nget_name from xml, css_key: " + css_key
        end
        puts list
      end

      return list
    end

    def get_component_name_list(css_key, type)
      list = Array.new()
      @manifest_xml.children.each do |parent|
        parent.css(css_key).each do |item|
          if type != nil and type != item.attr('type')
            next
          end

          # sim and os_abstraction are an exception
          name = item.attr('name')
          if "sim" == name or "os_abstraction" == name
            list.push(name) if !list.include?(name)
            next
          end

          item.css("/source").each do |source|
            if "src" == source.attr('type')
              path = source.attr('path')
              name = path.split('/').last
              list.push(name) if !list.include?(name)
              break # the first src path, last folder name is component name
            end
          end
        end
      end

      if DEBUG
        if type
          puts "\get_component_name_list from xml, css_key: " + css_key + " type: " + type
        else
          puts "\get_component_name_list from xml, css_key: " + css_key
        end
        puts list
      end

      return list
    end

    def get_componets(type)
      #TODO
      #Get all information, including the path and source mask
    end
end

class Verification
  attr_reader :sdk_path, :ref_part_numbers_excel, :manifest, :source, :result, :excel
  public
    def initialize()
      @result = Hash.new()
      @excel = WIN32OLE.new("EXCEL.APPLICATION")
    end

    def process_cmdargs()
      opt_parser = OptionParser.new do | opts |
        opts.on("-s", "--sdk [SDK installation path]", String, \
          "The SDK source code folder path after installing") do | value |
            @sdk_path = value
        end
        opts.on("-f", "--file [Optional -- derived parts number excel file]", String, \
          "Make sure the reference excel file has correct CPU part column") do | value |
            @ref_part_numbers_excel = value
        end
        # help option - print help and ends
        opts.on("-h", "--help", "print this help\n\n") do
            puts(opts)
            puts "Example:\nverify_manifest.rb -s C:/Freescale/KSDK_1.3.0 [-f C:/Part_Number_Support.xlsx]\n"
            exit(0)
        end
      end

      opt_parser.parse!

      if !@sdk_path
        puts(opt_parser)
        exit(1)
      end

      @manifest = ManifestInfo.new(sdk_path)
      @source = SDKSource.new(sdk_path)
    end

    def compare_lists()
      compare_list(manifest.get_board_list(), source.get_board_list(), "board")
      compare_list(manifest.get_device_list(), source.get_device_list(), "device")
      compare_list(manifest.get_derived_parts_list(), source.get_derived_parts_list(), "derived parts in registers header")
      compare_list(manifest.get_driver_list(), source.get_driver_list(), "driver")
      compare_list(manifest.get_hal_list(), source.get_hal_list(), "hal")
    end

    def verify_components()
      verify_components_type(manifest.get_driver_components(), "driver")
      verify_components_type(manifest.get_hal_components(), "hal")
      verify_components_type(manifest.get_other_components(), "other")
    end

    def verify_derived_parts_ref()
      if !@ref_part_numbers_excel
        puts "Not provide the reference part number excel, skip!"
        return
      end

      cpu_list_prd = Array.new()

      @excel.Workbooks.Open(@ref_part_numbers_excel)
      objSheet = @excel.Sheets(SHEET_NAME)
      objSheet.Select

      for start_index in (CPU_NAME_ROW_START..CPU_NAME_ROW_END) do
        value = (objSheet.Range("#{CPU_NAME_CLOUMN}#{start_index}").Value)

        # some cell is empty because it's merged
        next if nil == value or value.length <= 0

        # some cell has unknow ?, remove them, then split by ','
        cpu_list = value.gsub(/\?/, "").split(',')
        cpu_list.each do |item|
          cpu = item.strip() if item != nil
          puts "CPU item: #{cpu}" if DEBUG
          cpu_list_prd.push(cpu) if cpu != nil and cpu.length > 1 and !cpu_list_prd.include?(cpu)
        end
      end

      @excel.Quit() if @excel != nil

      if DEBUG
        puts "Get CPU list from the PRD excel:"
        puts cpu_list_prd
      end

      compare_list(manifest.get_derived_parts_list(), cpu_list_prd, "derived parts in PRD excel")
    end

    def dump_result()
      puts @result.to_yaml
      File.open("manifest_verification_result.yml", 'w') {|file| file.write @result.to_yaml}
    end

  private
    def compare_list(manifest_list, source_list, type)
      puts "compare list: " + type if DEBUG

      manifest_checklist = manifest_list.dup
      source_checklist = source_list.dup
      manifest_list.each do |item|
        if source_checklist.include?(item)
          source_checklist.delete(item)
          manifest_checklist.delete(item)
        end
      end

      if manifest_checklist.length <= 0 and source_checklist.length <= 0
        @result [type + " --- manifest verification"] = ["OK"]
      else
        if manifest_checklist.length > 0
          @result[type + " --- manifest redundant"] = manifest_checklist
        end

        if source_checklist.length > 0
          @result[type + " --- manifest missing"] = source_checklist
        end
      end
    end

    def verify_components_type(components, type)
      #TODO
      #Check each components path and source mask is correct, could be found
    end
end


#main
verification = Verification.new()
verification.process_cmdargs()

verification.compare_lists()
verification.verify_components()
verification.verify_derived_parts_ref()
verification.dump_result()

