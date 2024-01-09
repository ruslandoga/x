defmodule X.Zip do
  @moduledoc "Basic streamable Zip"

  # TODO or maybe just use https://github.com/dscout/zap
  # why did I decide against using it the last time?
  # or https://github.com/ananthakumaran/zstream

  import Bitwise

  @spec start_entry(String.t(), Keyword.t()) :: {entry :: map, iodata}
  def start_entry(name, opts \\ []) do
    mtime = NaiveDateTime.from_erl!(:calendar.local_time())
    nsize = byte_size(name)
    compression = opts[:compression] || 0

    # see 4.4 in https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
    local_header = <<
      # local file header signature
      0x04034B50::32-little,
      # version needed to extract
      20::16-little,
      # general purpose bit flag (bit 3: data descriptor, bit 11: utf8 name)
      0x0008 ||| 0x0800::16-little,
      # compression method
      compression::16-little,
      # last mod time
      dos_time(mtime)::16-little,
      # last mod date
      dos_date(mtime)::16-little,
      # crc-32
      0::32,
      # compressed size
      0::32,
      # uncompressed size
      0::32,
      # file name length
      nsize::16-little,
      # extra field length
      0::16,
      # file name
      name::bytes
    >>

    entry = %{
      header: %{
        size: byte_size(local_header),
        name: name,
        nsize: nsize
      },
      entity: %{
        crc: nil,
        size: nil,
        usize: 0,
        csize: 0
      },
      size: nil
    }

    {entry, local_header}
  end

  @spec grow_entry(entry, iodata) :: entry when entry: map
  def grow_entry(entry, data) do
    %{entity: %{crc: crc, usize: usize, csize: csize} = entity} = entry
    size = IO.iodata_length(data)

    crc =
      if crc do
        :erlang.crc32(crc, data)
      else
        :erlang.crc32(data)
      end

    %{entry | entity: %{entity | crc: crc, usize: usize + size, csize: csize + size}}
  end

  @spec end_entry(entry) :: {entry, iodata} when entry: map
  def end_entry(entry) do
    %{
      header: %{size: header_size},
      entity: %{crc: crc, usize: usize, csize: csize} = entity
    } =
      entry

    data_descriptor = <<
      # local file entry signature
      0x08074B50::32-little,
      # crc-32 for the entity
      crc::32-little,
      # compressed size, just the size since we aren't compressing
      csize::32-little,
      # uncompressed size
      usize::32-little
    >>

    entry = %{
      entry
      | entity: %{entity | size: byte_size(data_descriptor) + csize},
        size: byte_size(data_descriptor) + csize + header_size
    }

    {entry, data_descriptor}
  end

  @spec encode_central_directory([entry]) :: iodata when entry: map
  def encode_central_directory(entries) do
    context =
      Enum.reduce(entries, %{frames: [], count: 0, offset: 0, size: 0}, fn entry, acc ->
        header = encode_central_file_header(acc, entry)

        acc
        |> Map.update!(:frames, &[header.frame | &1])
        |> Map.update!(:count, &(&1 + 1))
        |> Map.update!(:offset, &(&1 + header.offset))
        |> Map.update!(:size, &(&1 + header.size))
      end)

    frame = <<
      0x06054B50::32-little,
      # number of this disk
      0::16,
      # number of the disk w/ ECD
      0::16,
      # total number of entries in this disk
      context.count::16-little,
      # total number of entries in the ECD
      context.count::16-little,
      # size central directory
      context.size::32-little,
      # offset central directory
      context.offset::32-little,
      # comment length
      0::16
    >>

    [:lists.reverse(context.frames), frame]
  end

  defp encode_central_file_header(context, %{header: header, entity: entity}) do
    mtime = NaiveDateTime.from_erl!(:calendar.local_time())

    frame = <<
      # central file header signature
      0x02014B50::32-little,
      # version made by
      52::16-little,
      # version to extract
      20::16-little,
      # general purpose bit flag (bit 3: data descriptor, bit 11: utf8 name)
      0x0008 ||| 0x0800::16-little,
      # compression method
      0::16-little,
      # last mod file time
      dos_time(mtime)::16-little,
      # last mod date
      dos_date(mtime)::16-little,
      # crc-32
      entity.crc::32-little,
      # compressed size
      entity.csize::32-little,
      # uncompressed size
      entity.usize::32-little,
      # file name length
      header.nsize::16-little,
      # extra field length
      0::16,
      # file comment length
      0::16,
      # disk number start
      0::16,
      # internal file attribute
      0::16,
      # external file attribute (unix permissions, rw-r--r--)
      (0o10 <<< 12 ||| 0o644) <<< 16::32-little,
      # relative offset header
      context.offset::32-little,
      # file name
      header.name::bytes
    >>

    %{frame: frame, size: byte_size(frame), offset: header.size + entity.size}
  end

  defp dos_time(time) do
    round(time.second / 2 + (time.minute <<< 5) + (time.hour <<< 11))
  end

  defp dos_date(time) do
    round(time.day + (time.month <<< 5) + ((time.year - 1980) <<< 9))
  end
end
