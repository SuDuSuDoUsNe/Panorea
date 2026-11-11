{$MODE OBJFPC}
{$H+}
program midi2music;

uses sysutils, classes;

const
    NOTE_EN: array[0..11] of string = ('C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B');
    NOTE_IT: array[0..11] of string = ('DO', 'DO#', 'RE', 'RE#', 'MI', 'FA', 'FA#', 'SOL', 'SOL#', 'LA', 'LA#', 'SI');
    NOTE_DE: array[0..11] of string = ('C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'B', 'H');

type
    TFourChar = array[0..3] of Char;

    TNoteEvent = record
        Tick: Int64;
        NoteNum: Byte;
        Velocity: Byte;
        IsOn: Boolean;
    end;

var
    MidiStream: TFileStream;
    OutFile: TextFile;
    InName, OutName: string;
    Events: array of TNoteEvent;
    EventCount: Integer;
    TimeDivision: Word;
    CurrentTick: Int64;
    SelectedSystem: string;

function Swap16(val: Word): Word;
begin
    Result := ((val and $FF00) shr 8) or ((val and $00FF) shl 8);
end;

function Swap32(val: Cardinal): Cardinal;
begin
    Result := ((val and $FF000000) shr 24) or
              ((val and $00FF0000) shr 8)  or
              ((val and $0000FF00) shl 8)  or
              ((val and $000000FF) shl 24);
end;

function ReadVarLen(Stream: TFileStream): Int64;
var
    b: Byte;
    value: Int64;
begin
    value := 0;
    repeat
        Stream.Read(b, 1);
        value := (value shl 7) or (b and $7F);
    until (b and $80) = 0;
    Result := value;
end;

procedure ParseTrack(Stream: TFileStream; Length: Cardinal);
var
    EndPos: Int64;
    delta: Int64;
    status, b1, b2: Byte;
    metaType: Byte;
    metaLen: Int64;
    i: Integer;
begin
    EndPos := Stream.Position + Length;
    status := 0;

    while Stream.Position < EndPos do
    begin
        delta := ReadVarLen(Stream);
        CurrentTick := CurrentTick + delta;

        Stream.Read(b1, 1);
        if (b1 and $80) <> 0 then
        begin
            status := b1;
            Stream.Read(b1, 1);
        end;

        case (status and $F0) of
            $80: begin // Note Off
                    Stream.Read(b2, 1);
                    SetLength(Events, EventCount + 1);
                    Events[EventCount].Tick := CurrentTick;
                    Events[EventCount].NoteNum := b1;
                    Events[EventCount].Velocity := 0;
                    Events[EventCount].IsOn := false;
                    inc(EventCount);
                end;
            $90: begin // Note On
                    Stream.Read(b2, 1);
                    SetLength(Events, EventCount + 1);
                    Events[EventCount].Tick := CurrentTick;
                    Events[EventCount].NoteNum := b1;
                    Events[EventCount].Velocity := b2;
                    Events[EventCount].IsOn := (b2 > 0);
                    inc(EventCount);
                end;
            $A0, $B0, $E0: Stream.Read(b2, 1);
            $C0, $D0: ;
            $F0: begin
                    if status = $FF then
                    begin
                        metaType := b1;
                        metaLen := ReadVarLen(Stream);
                        for i := 1 to metaLen do Stream.Read(b1, 1);
                    end;
                end;
        end;
    end;
end;

function MidiNoteToPanorea(NoteNum: Byte): string;
var
    noteIndex, octave: Integer;
begin
    noteIndex := NoteNum mod 12;
    octave := (NoteNum div 12) - 1;
    if octave < 3 then octave := 3;

    if SelectedSystem = 'it' then Result := NOTE_IT[noteIndex] + IntToStr(octave)
    else if SelectedSystem = 'de' then Result := NOTE_DE[noteIndex] + IntToStr(octave)
    else Result := NOTE_EN[noteIndex] + IntToStr(octave);
end;

procedure SortEvents();
var
    i, j: Integer;
    temp: TNoteEvent;
begin
    for i := 0 to EventCount - 2 do
        for j := i + 1 to EventCount - 1 do
            if Events[i].Tick > Events[j].Tick then
            begin
                temp := Events[i];
                Events[i] := Events[j];
                Events[j] := temp;
            end;
end;

procedure GenerateMusicFile();
var
    i, k: Integer;
    lastTick, currentBlockTick, tickDiff: Int64;
    msDuration: Integer;
    chordStr: string;
    tempoBPM, msPerTick: Double;
    ActiveNotes: array[0..127] of Boolean; // Tableau statique pour éviter les corruptions
    NotesInChord: array of Byte;
    ChordCount: Integer;
begin
    if EventCount = 0 then Exit;

    SortEvents();

    tempoBPM := 120.0;
    msPerTick := (60000.0 / tempoBPM) / TimeDivision;

    Assign(OutFile, OutName);
    Rewrite(OutFile);
    writeln(OutFile, 'NOTATION: ', SelectedSystem);
    writeln(OutFile, 'MUSIC:');

    for i := 0 to 127 do ActiveNotes[i] := false;

    lastTick := Events[0].Tick; // Corrigé ici
    currentBlockTick := Events[0].Tick; // Corrigé ici
    SetLength(NotesInChord, 0);
    ChordCount := 0;

    if lastTick > 0 then
    begin
        msDuration := Round(lastTick * msPerTick);
        if msDuration > 10 then
            write(OutFile, ':', msDuration, ' ');
    end;

    for i := 0 to EventCount - 1 do
    begin
        if Events[i].Tick > currentBlockTick then
        begin
            tickDiff := Events[i].Tick - currentBlockTick;
            msDuration := Round(tickDiff * msPerTick);

            if msDuration > 10 then
            begin
                if ChordCount > 0 then
                begin
                    chordStr := '';
                    for k := 0 to ChordCount - 1 do
                    begin
                        if k > 0 then chordStr := chordStr + '/';
                        chordStr := chordStr + MidiNoteToPanorea(NotesInChord[k]);
                    end;
                    write(OutFile, chordStr, ':', msDuration, ' ');
                end
                else
                begin
                    write(OutFile, ':', msDuration, ' ');
                end;
            end;

            currentBlockTick := Events[i].Tick;

            ChordCount := 0;
            SetLength(NotesInChord, 0);
            for k := 0 to 127 do
            begin
                if ActiveNotes[k] and (ChordCount < 4) then
                begin
                    inc(ChordCount);
                    SetLength(NotesInChord, ChordCount);
                    NotesInChord[ChordCount - 1] := k;
                end;
            end;
        end;

        if Events[i].IsOn then
            ActiveNotes[Events[i].NoteNum] := true
        else
            ActiveNotes[Events[i].NoteNum] := false;

        if Events[i].IsOn then
        begin
            if ChordCount < 4 then
            begin
                inc(ChordCount);
                SetLength(NotesInChord, ChordCount);
                NotesInChord[ChordCount - 1] := Events[i].NoteNum;
            end;
        end;
    end;

    writeln(OutFile, '');
    Close(OutFile);
end;

var
    id: TFourChar;
    sz: Cardinal;
    fmt, tracks: Word;
    i: Integer;
    arg: string;

begin
    if ParamCount < 1 then
    begin
        writeln('Usage: midi2music <file.mid> [--en | --it | --de]');
        Halt(1);
    end;

    InName := ParamStr(1);
    OutName := ChangeFileExt(InName, '.music');
    SelectedSystem := 'en';

    if ParamCount > 1 then
    begin
        arg := LowerCase(ParamStr(2));
        if arg = '--it' then SelectedSystem := 'it'
        else if arg = '--de' then SelectedSystem := 'de'
        else if arg = '--en' then SelectedSystem := 'en';
    end;

    if not FileExists(InName) then
    begin
        writeln('Error: File ', InName, ' not found.');
        Halt(1);
    end;

    MidiStream := TFileStream.Create(InName, fmOpenRead);
    try
    EventCount := 0;
    SetLength(Events, 0);

    MidiStream.Read(id[0], 4); // Corrigé pour le type TFourChar statique
    MidiStream.Read(sz, 4);
    sz := Swap32(sz);

    if (id[0] <> 'M') or (id[1] <> 'T') or (id[2] <> 'h') or (id[3] <> 'd') or (sz <> 6) then
    begin
        writeln('Error: Invalid MIDI header structure.');
        Halt(1);
    end;

    MidiStream.Read(fmt, 2);
    MidiStream.Read(tracks, 2);
    MidiStream.Read(TimeDivision, 2);

    fmt := Swap16(fmt);
    tracks := Swap16(tracks);
    TimeDivision := Swap16(TimeDivision);

    for i := 1 to tracks do
    begin
        MidiStream.Read(id[0], 4);
        MidiStream.Read(sz, 4);
        sz := Swap32(sz);

        if (id[0] = 'M') and (id[1] = 'T') and (id[2] = 'r') and (id[3] = 'k') then
        begin
            CurrentTick := 0;
            ParseTrack(MidiStream, sz);
        end
        else
            MidiStream.Position := MidiStream.Position + sz;
    end;

    writeln('Notation set to: ', SelectedSystem);
    GenerateMusicFile();
    writeln('Successfully generated: ', OutName);

    finally
    MidiStream.Free;
end;
end.
