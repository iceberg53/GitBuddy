unit Git.DiffParser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TCharChange = (ccUnchanged, ccAdded, ccDeleted);

  TCharMatch = record
    Character: Char;
    State: TCharChange;
  end;

  TCharMatchArray = array of TCharMatch;

  TGitDiffMatcher = class
  public
    class function CompareLines(const OldLine, NewLine: string; out OldMatches, NewMatches: TCharMatchArray): Boolean;
  end;

implementation

class function TGitDiffMatcher.CompareLines(const OldLine, NewLine: string; out OldMatches, NewMatches: TCharMatchArray): Boolean;
var
  CleanOld, CleanNew: string;
  LenOld, LenNew, MaxLen, I, MatchCount: Integer;
begin
  OldMatches := nil;
  NewMatches := nil;

  Result := False;
  MatchCount := 0;

  if (Length(OldLine) <= 1) or (Length(NewLine) <= 1) then Exit;

  CleanOld := Copy(OldLine, 2, Length(OldLine) - 1);
  CleanNew := Copy(NewLine, 2, Length(NewLine) - 1);

  LenOld := Length(CleanOld);
  LenNew := Length(CleanNew);

  if (LenOld = 0) or (LenNew = 0) then Exit;

  SetLength(OldMatches, LenOld);
  SetLength(NewMatches, LenNew);

  for I := 1 to LenOld do
  begin
    OldMatches[I - 1].Character := CleanOld[I];
    OldMatches[I - 1].State := ccDeleted;
  end;

  for I := 1 to LenNew do
  begin
    NewMatches[I - 1].Character := CleanNew[I];
    NewMatches[I - 1].State := ccAdded;
  end;

  if LenOld > LenNew then MaxLen := LenOld else MaxLen := LenNew;

  for I := 0 to MaxLen - 1 do
  begin
    if (I < LenOld) and (I < LenNew) then
    begin
      if OldMatches[I].Character = NewMatches[I].Character then
      begin
        OldMatches[I].State := ccUnchanged;
        NewMatches[I].State := ccUnchanged;
        Inc(MatchCount); // Track how many characters actually line up
      end;
    end;
  end;

  // 👈 INTRA-LINE THRESHOLD CHECK:
  // Only accept the match if the two lines share at least 20% positional similarity.
  // If it's a blind overwrite, this returns False and falls back to clean line-only colors!
  if (MaxLen > 0) and ((MatchCount / MaxLen) >= 0.20) then
    Result := (MatchCount > 0);
end;

end.

