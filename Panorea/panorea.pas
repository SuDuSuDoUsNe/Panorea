program panorea;
uses unix, sysutils;

const
    SAMPLING_RATE = 8000;
    TEMP_FILE_0 = '/tmp/chan0.raw';
    TEMP_FILE_1 = '/tmp/chan1.raw';
    TEMP_FILE_2 = '/tmp/chan2.raw';
    TEMP_FILE_3 = '/tmp/chan3.raw';

var
    audio_files: array[0..3] of file of Byte;
    system_choice: char;
    partition_text: string;
    file_path: string;
    text_file: TextFile;
    line: string;
    is_music_section: boolean;
    export_choice: char;
    export_name: string;
    show_example: boolean;

function IsValidDurationText(const duration_text: string): Boolean;
var
    duration_value: Integer;
begin
    if not TryStrToInt(duration_text, duration_value) then
        Exit(False);
    Result := duration_value > 0;
end;

function NoteMatchesPitch(const note_text, pitch: string): Boolean;
var
    octave_text: string;
    octave_value: Integer;
    i, first_digit: Integer;
begin
    Result := False;
    if Copy(note_text, 1, Length(pitch)) <> pitch then
        Exit;

    octave_text := Copy(note_text, Length(pitch) + 1, Length(note_text));
    if octave_text = '' then
    begin
        // The note parser has historically treated an omitted octave as octave 4.
        Result := True;
        Exit;
    end;

    first_digit := 1;
    if octave_text[1] = '-' then
        first_digit := 2;
    if first_digit > Length(octave_text) then
        Exit;

    for i := first_digit to Length(octave_text) do
        if not (octave_text[i] in ['0'..'9']) then
            Exit;

    Result := TryStrToInt(octave_text, octave_value);
end;

function IsValidNoteToken(const note_text: string; notation: char): Boolean;
var
    normalized_note: string;
begin
    normalized_note := UpperCase(Trim(note_text));
    case notation of
        '1':
            Result := NoteMatchesPitch(normalized_note, 'C') or
                      NoteMatchesPitch(normalized_note, 'DB') or
                      NoteMatchesPitch(normalized_note, 'C#') or
                      NoteMatchesPitch(normalized_note, 'D') or
                      NoteMatchesPitch(normalized_note, 'E') or
                      NoteMatchesPitch(normalized_note, 'F') or
                      NoteMatchesPitch(normalized_note, 'G') or
                      NoteMatchesPitch(normalized_note, 'A') or
                      NoteMatchesPitch(normalized_note, 'BB') or
                      NoteMatchesPitch(normalized_note, 'A#') or
                      NoteMatchesPitch(normalized_note, 'B');
        '2':
            Result := NoteMatchesPitch(normalized_note, 'DO') or
                      NoteMatchesPitch(normalized_note, 'REB') or
                      NoteMatchesPitch(normalized_note, 'DO#') or
                      NoteMatchesPitch(normalized_note, 'RE') or
                      NoteMatchesPitch(normalized_note, 'MI') or
                      NoteMatchesPitch(normalized_note, 'FA') or
                      NoteMatchesPitch(normalized_note, 'SOL') or
                      NoteMatchesPitch(normalized_note, 'LA') or
                      NoteMatchesPitch(normalized_note, 'SIB') or
                      NoteMatchesPitch(normalized_note, 'LA#') or
                      NoteMatchesPitch(normalized_note, 'SI');
        '3':
            Result := NoteMatchesPitch(normalized_note, 'C') or
                      NoteMatchesPitch(normalized_note, 'DES') or
                      NoteMatchesPitch(normalized_note, 'D') or
                      NoteMatchesPitch(normalized_note, 'E') or
                      NoteMatchesPitch(normalized_note, 'F') or
                      NoteMatchesPitch(normalized_note, 'G') or
                      NoteMatchesPitch(normalized_note, 'A') or
                      NoteMatchesPitch(normalized_note, 'B') or
                      NoteMatchesPitch(normalized_note, 'H');
        else
            Result := False;
    end;
end;

function ValidatePartition(const partition: string; notation: char): Boolean;
var
    remaining, chunk, chord_text, duration_text, note_list, note_text: string;
    space_pos, colon_pos, slash_pos, note_count: Integer;
begin
    Result := False;
    remaining := Trim(partition) + ' ';

    while Length(remaining) > 0 do
    begin
        space_pos := Pos(' ', remaining);
        if space_pos = 0 then
            Break;
        chunk := Copy(remaining, 1, space_pos - 1);
        Delete(remaining, 1, space_pos);

        if chunk = '' then
            Continue;

        colon_pos := Pos(':', chunk);
        if colon_pos = 0 then
        begin
            writeln('Error: Invalid duration format in "', chunk,
                    '". Expected NOTE:DURATION.');
            Exit;
        end;

        chord_text := Copy(chunk, 1, colon_pos - 1);
        duration_text := Copy(chunk, colon_pos + 1, Length(chunk));
        if not IsValidDurationText(duration_text) then
        begin
            writeln('Error: Invalid duration format in "', chunk,
                    '". Duration must be a positive integer.');
            Exit;
        end;

        // An empty chord is a rest. Otherwise every slash-separated item
        // must be a valid note; empty items such as C4//E4 are malformed.
        if chord_text <> '' then
        begin
            note_list := chord_text + '/';
            note_count := 0;
            while Length(note_list) > 0 do
            begin
                slash_pos := Pos('/', note_list);
                if slash_pos = 0 then
                    Break;
                note_text := Trim(Copy(note_list, 1, slash_pos - 1));
                Delete(note_list, 1, slash_pos);

                if note_text = '' then
                begin
                    writeln('Error: Invalid note format in "', chunk,
                            '". Empty notes are not allowed in a chord.');
                    Exit;
                end;

                Inc(note_count);
                if note_count > 4 then
                begin
                    writeln('Error: More than 4 notes polyphony is not supported.');
                    Exit;
                end;

                if not IsValidNoteToken(note_text, notation) then
                begin
                    writeln('Error: Invalid note format in "', note_text,
                            '" for the selected notation system.');
                    Exit;
                end;
            end;
        end;
    end;

    Result := True;
end;

procedure GenerateChannelsNotes(chord_string: string; duration_ms: Integer; system: char);
var
    i, j, sample_count, active_tracks, p, track: Integer;
    value: Byte;
    angle: Double;
    current_chunk, n: string;
    octave_num: Integer;
    base_freq: Double;
    cycle_samples: Double;
    freq_array: array[0..3] of Double;
begin
    active_tracks := 0;
    current_chunk := chord_string + '/';

    // 1. FREQUENCES EXTRACTION
    while (Length(current_chunk) > 0) and (active_tracks < 4) do
    begin
        p := Pos('/', current_chunk);
        if p = 0 then break;
        n := UpperCase(Trim(Copy(current_chunk, 1, p - 1)));
        Delete(current_chunk, 1, p);

        base_freq := 0;
        if Length(n) > 0 then
        begin
            j := Length(n);
            while (j > 0) and (n[j] in ['0'..'9', '-']) do dec(j);

            if system = '1' then // English
            begin
                if Copy(n, 1, j) = 'C'   then base_freq := 261.63
                else if (Copy(n, 1, j) = 'DB') or (Copy(n, 1, j) = 'C#') then base_freq := 277.18
                else if Copy(n, 1, j) = 'D'   then base_freq := 293.66
                else if Copy(n, 1, j) = 'E'   then base_freq := 329.63
                else if Copy(n, 1, j) = 'F'   then base_freq := 349.23
                else if Copy(n, 1, j) = 'G'   then base_freq := 392.00
                else if Copy(n, 1, j) = 'A'   then base_freq := 440.00
                else if (Copy(n, 1, j) = 'BB') or (Copy(n, 1, j) = 'A#') then base_freq := 466.16
                else if Copy(n, 1, j) = 'B'   then base_freq := 493.88;
            end
            else if system = '2' then // Italian / French
            begin
                if Copy(n, 1, j) = 'DO'  then base_freq := 261.63
                else if (Copy(n, 1, j) = 'REB') or (Copy(n, 1, j) = 'DO#') then base_freq := 277.18
                else if Copy(n, 1, j) = 'RE'  then base_freq := 293.66
                else if Copy(n, 1, j) = 'MI'  then base_freq := 329.63
                else if Copy(n, 1, j) = 'FA'  then base_freq := 349.23
                else if Copy(n, 1, j) = 'SOL' then base_freq := 392.00
                else if Copy(n, 1, j) = 'LA'  then base_freq := 440.00
                else if (Copy(n, 1, j) = 'SIB') or (Copy(n, 1, j) = 'LA#') then base_freq := 466.16
                else if Copy(n, 1, j) = 'SI'  then base_freq := 493.88;
            end
            else if system = '3' then // German
            begin
                if Copy(n, 1, j) = 'C'   then base_freq := 261.63
                else if Copy(n, 1, j) = 'DES' then base_freq := 277.18
                else if Copy(n, 1, j) = 'D'   then base_freq := 293.66
                else if Copy(n, 1, j) = 'E'   then base_freq := 329.63
                else if Copy(n, 1, j) = 'F'   then base_freq := 349.23
                else if Copy(n, 1, j) = 'G'   then base_freq := 392.00
                else if Copy(n, 1, j) = 'A'   then base_freq := 440.00
                else if Copy(n, 1, j) = 'B'   then base_freq := 466.16
                else if Copy(n, 1, j) = 'H'   then base_freq := 493.88;
            end;

            if base_freq > 0 then
            begin
                octave_num := StrToIntDef(Copy(n, j + 1, Length(n)), 4);
                base_freq := base_freq * Exp((octave_num - 4) * Ln(2));
            end;
        end;

        freq_array[active_tracks] := base_freq;
        inc(active_tracks);
    end;

    for track := active_tracks to 3 do
        freq_array[track] := 0;

    sample_count := Round((SAMPLING_RATE * duration_ms) / 1000);

    for track := 0 to 3 do
    begin
        if freq_array[track] > 0 then
        begin
            cycle_samples := SAMPLING_RATE / freq_array[track];
            sample_count := Round(Round(sample_count / cycle_samples) * cycle_samples);
            Break;
        end;
    end;
    
    // 2. SIMULTANEOUS WRITING IN EVERY CANAL FILE
    for track := 0 to 3 do
    begin
        for i := 0 to sample_count - 1 do
        begin
            if freq_array[track] = 0 then
                value := 127
            else
            begin
                angle := 2.0 * Pi * freq_array[track] * i / SAMPLING_RATE;
                value := Round(127.0 + 127.0 * Sin(angle));
            end;
            Write(audio_files[track], value);
        end;

        for i := 0 to Round((SAMPLING_RATE * 25) / 1000) - 1 do
        begin
            value := 127;
            Write(audio_files[track], value);
        end;
    end;
end;

function PlayPartition(partition: string; system: char): Boolean;
var
    p, chunk: string;
    space_pos, colon_pos: Integer;
    chord_text: string;
    duration_ms: Integer;
    total_duration_ms: Integer;
    track: Integer;
begin
    Result := False;
    if not ValidatePartition(partition, system) then
        Exit;

    p := Trim(partition) + ' ';

    Assign(audio_files[0], TEMP_FILE_0); Rewrite(audio_files[0]);
    Assign(audio_files[1], TEMP_FILE_1); Rewrite(audio_files[1]);
    Assign(audio_files[2], TEMP_FILE_2); Rewrite(audio_files[2]);
    Assign(audio_files[3], TEMP_FILE_3); Rewrite(audio_files[3]);

    total_duration_ms := 0;

    while Length(p) > 0 do
    begin
        space_pos := Pos(' ', p);
        if space_pos = 0 then break;
        chunk := Copy(p, 1, space_pos - 1);
        Delete(p, 1, space_pos);

        colon_pos := Pos(':', chunk);
        if colon_pos > 0 then
        begin
            chord_text := Copy(chunk, 1, colon_pos - 1);
            duration_ms := StrToIntDef(Copy(chunk, colon_pos + 1, Length(chunk)), 500);

            total_duration_ms := total_duration_ms + duration_ms + 25;
            GenerateChannelsNotes(chord_text, duration_ms, system);
        end;
    end;

    for track := 0 to 3 do Close(audio_files[track]);

    // Have you ever tasted Camembert ? No ? Well when you taste it, either you love it, or you hate it to death.
    // This background execution multi-process mixing method is exactly like Camembert.
    fpSystem('aplay -r 8000 -f U8 ' + TEMP_FILE_0 + ' > /dev/null 2>&1 &');
    fpSystem('aplay -r 8000 -f U8 ' + TEMP_FILE_1 + ' > /dev/null 2>&1 &');
    fpSystem('aplay -r 8000 -f U8 ' + TEMP_FILE_2 + ' > /dev/null 2>&1 &');
    fpSystem('aplay -r 8000 -f U8 ' + TEMP_FILE_3 + ' > /dev/null 2>&1 &');

    fpSystem('sleep ' + FloatToStr(total_duration_ms / 1000 + 0.5));
    fpSystem('rm -f ' + TEMP_FILE_0 + ' ' + TEMP_FILE_1 + ' ' + TEMP_FILE_2 + ' ' + TEMP_FILE_3);
    Result := True;
end;

begin
    // -------------------------------------------------------------------------
    // FILE INGESTION PIPELINE (CLI ARGUMENT PASSTHROUGH)
    // -------------------------------------------------------------------------
    if ParamCount > 0 then
    begin
        file_path := ParamStr(1);

        if ExtractFileExt(file_path) <> '.music' then
        begin
            writeln('Error: Only .music files are supported.');
            Exit;
        end;

        if FileExists(file_path) then
        begin
            Assign(text_file, file_path);
            Reset(text_file);
            system_choice := '1';
            partition_text := '';
            is_music_section := false;

            while not Eof(text_file) do
            begin
                Readln(text_file, line);
                line := Trim(line);

                if Pos('NOTATION:', UpperCase(line)) = 1 then
                begin
                    if Pos('EN', UpperCase(line)) > 0 then system_choice := '1'
                    else if Pos('IT', UpperCase(line)) > 0 then system_choice := '2'
                    else if Pos('DE', UpperCase(line)) > 0 then system_choice := '3';
                end
                else if Pos('MUSIC:', UpperCase(line)) = 1 then
                    is_music_section := true
                else if is_music_section and (Length(line) > 0) then
                    partition_text := partition_text + line + ' ';
            end;

            Close(text_file);
            writeln('-- PANOREA CLI LOADER --');
            writeln('Playing file: ', file_path);

            PlayPartition(partition_text, system_choice);
            Exit;
        end;
    end;

    // -------------------------------------------------------------------------
    // INTERACTIVE MAN-MACHINE INTERFACE (INTERACTIVE MENU MODE)
    // -------------------------------------------------------------------------
    writeln('-- PANOREA --');
    writeln('1. English          (C4, Db4, E4...)');
    writeln('2. Italian / French (DO4, REb4, MI4...)');
    writeln('3. German           (C4, DES4, H4...)');
    writeln('Q. Quit');

    repeat
        write('Choose your notation system: ');
        readln(system_choice);
        if (system_choice = 'q') or (system_choice = 'Q') then Exit;
    until (system_choice = '1') or (system_choice = '2') or (system_choice = '3');

    writeln('');
    writeln('=== NOTATION SYSTEM SET UP ===');
    writeln('-> To play a note: NOTE_OCTAVE:DURATION');
    writeln('-> To make a REST / PAUSE: leave the note blank, type only :DURATION (e.g. :400)');
    writeln('-> MULTI-PROCESS POLYPHONY: Separate notes by / to trigger multiple aplays (e.g. C4/E4/G4:500)');
    writeln('-> Low notes (lower than C3) are not supported, these notes will do weird things.');
    writeln('==============================');

    show_example := true;

    while true do
    begin
        writeln('');
        writeln('Enter notes separated by spaces. Type "Q" to quit, "CLR" to clear screen.');
        if show_example then
        begin
            if system_choice = '1' then
                writeln('Example: C4/E4/G4:400 :200 C4/F4/A4:400')
            else if system_choice = '2' then
                writeln('Example: DO4/MI4/SOL4:400 :200 DO4/FA4/LA4:400')
            else
                writeln('Example: C4/E4/G4:400 :200 C4/F4/A4:400');
            show_example := false;
        end;
        write('Your partition: ');
        readln(partition_text);
        if (UpperCase(Trim(partition_text)) = 'Q') then Break;
        if (UpperCase(Trim(partition_text)) = 'CLR') then
        begin
            fpSystem('clear');
            Continue;
        end;
        if Length(Trim(partition_text)) = 0 then Continue;
        writeln('Calculating and playing...');
        if not PlayPartition(partition_text, system_choice) then
            Continue;
// ---------------------------------------------------------------------
// PERSISTENCE SUBSYSTEM (EXPORT MATRIX ROUTINE)
// ---------------------------------------------------------------------
        write('Do you want to export this partition to a .music file? (y/n): ');
        readln(export_choice);
        if (export_choice = 'y') or (export_choice = 'Y') then
        begin
            write('Enter filename (without extension): ');
            readln(export_name);
            export_name := export_name + '.music';
            Assign(text_file, export_name);
            {$I-}
            Rewrite(text_file);
            {$I+}
            if IOResult = 0 then
            begin
                if system_choice = '1' then writeln(text_file, 'NOTATION: en')
                else if system_choice = '2' then writeln(text_file, 'NOTATION: it')
                else if system_choice = '3' then writeln(text_file, 'NOTATION: de');
                writeln(text_file, 'MUSIC:');
                writeln(text_file, partition_text);
                Close(text_file);
                writeln('Partition successfully exported to ', export_name);
            end
            else
                writeln('Error: Could not write the file.');
        end;
    end;
end.
