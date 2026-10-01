# Build the local Windows mock package

There is no public binary download for this project. You can build a self-contained Windows x64 mock package on your own machine with the [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0):

```powershell
.\scripts\package-demo.ps1
```

The script creates a new folder and ZIP under the ignored `artifacts` directory; it does not delete earlier packages or upload anything. The first build restores the Microsoft runtime packs from the configured NuGet.org source. If the SDK supplies `LICENSE.txt` and `ThirdPartyNotices.txt`, the script copies them into `runtime-notices` inside the package.

Extract the ZIP, open PowerShell in that folder, and run:

```powershell
.\scripts\demo.ps1 -ExecutablePath .\m365scopedmail.exe
```

The package runs the same four local mock checks and needs no SDK, tenant, credentials, or network connection at runtime. It is for local review only. It is not a production build, and it does not prove Exchange or Graph authorization. Rebuild it after runtime security updates.

The project has no selected license. Runtime notices apply to the bundled .NET runtime; they do not establish a license for this project's source code.
