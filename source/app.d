import std.stdio;
import std.exception;
import std.getopt;
import std.file;
import std.concurrency;
import std.conv;
import std.string;
import std.format;

import core.thread;

import puppeteer.puppeteer;
import puppeteer.serial.BaudRate;
import puppeteer.serial.Parity;

immutable string loggerTidName = "loggerTid";

void main(string[] args)
{
	string devFilename = "";
	string outFilename = "puppeteerOut.txt";

	getopt(args,
		"dev|d", &devFilename,
		"out|o", &outFilename);

	enforce(devFilename != "" && exists(devFilename), "Please select an existing device using --dev [devicePath]");

	writeln("Opening dev file "~devFilename);
	auto puppeteer = new Puppeteer!short(devFilename, Parity.none, BaudRate.B9600);

	Tid loggerTid = spawn(
		(string outFilename)
		{
			bool shouldContinue = true;

			File outFile = File(outFilename, "w");

			while(shouldContinue)
			{
				receive(
				(MainMessage message)
				{
					if(message.message != "END")
					{
						outFile.writeln(message.message);
						outFile.flush();
					}
					else
					{
						shouldContinue = false;
						outFile.close();
					}
				});
			}
		}, outFilename);

	register(loggerTidName, loggerTid);

	void showMenu()
	{
		enum Options
		{
			start,
			stop,
			startPinMonitor,
			stopPinMonitor,
			startVarMonitor,
			stopVarMonitor,
			pwm,
            setAIAdapter,
            setVarMonitorAdapter,
			exit
		}

		void printOption(Options option, string optionMsg)
		{
			writeln(to!string(int(option)) ~ " - " ~ optionMsg);
		}

		PuppetListener listener = new PuppetListener(puppeteer);

		void addPinMonitor()
		{
			write("Which pin do you want to monitor? (-1 to cancel): ");
			int pinInput = -1;
			string input = readln().chomp();
			formattedRead(input, " %s", &pinInput);

			if(pinInput < 0)
				return;

			ubyte pin = to!ubyte(pinInput);

			listener.addPinListener(pin);
			writeln("Monitoring pin ",pin);
		}

		void removePinMonitor()
		{
			write("Which pin do you want to stop monitoring? (-1 to cancel): ");
			int pinInput = -1;
			string input = readln().chomp();
			formattedRead(input, " %s", &pinInput);

			if(pinInput < 0)
				return;

			ubyte pin = to!ubyte(pinInput);

			listener.removePinListener(pin);
			writeln("Stopped monitoring pin ",pin);
		}

		void addVarMonitor()
		{
			write("Which var do you want to monitor? (-1 to cancel): ");
			int varInput = -1;
			string input = readln().chomp();
			formattedRead(input, " %s", &varInput);

			if(varInput < 0)
				return;

			ubyte index = to!ubyte(varInput);

			listener.addVarListener!short(index);
			writeln("Monitoring variable ", index);
		}

		void removeVarMonitor()
		{
			write("Which var do you want to stop monitoring? (-1 to cancel): ");
			int varInput = -1;
			string input = readln().chomp();
			formattedRead(input, " %s", &varInput);

			if(varInput < 0)
				return;

			ubyte index = to!ubyte(varInput);

			listener.removeVarListener!short(index);
			writeln("Stopping monitoring variable ", index);
		}

		void setPWM()
		{
			write("Introduce pin and PWM value [pin-value] (-1 to cancel): ");

			int pinInput = -1;
			ubyte pwmValue;
			string input = readln().chomp();
			formattedRead(input, " %s-%s", &pinInput, &pwmValue);

			if(pinInput < 0)
				return;

			ubyte pin = to!ubyte(pinInput);

			writeln("Setting PWM pin ", pin, " to value ", pwmValue);
			puppeteer.setPWM(pin, pwmValue);
		}

        void setAIValueAdapter()
        {
            write("Introduce adaptation for analog input [pin-f(x)] (-1 to cancel): ");

            int pinInput = -1;
            string expr;
            string input = readln().chomp();
            formattedRead(input, " %s-%s", &pinInput, &expr);

            if(pinInput < 0)
            {
                return;
            }

            ubyte pin = to!ubyte(pinInput);
            puppeteer.setAnalogInputValueAdapter(pin, expr);

            writefln("Setting AI adapter for pin %s to f(x)=%s", pin, expr !is null ? expr : "x");
        }

        void setVarMonitorValueAdapter()
        {
            write("Introduce value adaptation for internal variable [varIndex-f(x)] (-1 to cancel): ");

            int varIndexInput = -1;
            string expr;
            string input = readln().chomp();
            formattedRead(input, " %s-%s", &varIndexInput, &expr);

            if(varIndexInput < 0)
                return;

            ubyte varIndex = to!ubyte(varIndexInput);
            puppeteer.setVarMonitorValueAdapter!short(varIndex, expr);

            writefln("Setting variable adapter for internal variable %s to f(x)=%s", varIndex, expr !is null ? expr : "x");
        }

		menu : while(true)
		{
			writeln("------");
			writeln("Available options:");
			with(Options)
			{
				printOption(start, "Start communication");
				printOption(stop, "Stop communication");
				printOption(startPinMonitor, "Monitor analog input");
				printOption(stopPinMonitor, "Stop monitoring analog input");
				printOption(startVarMonitor, "Monitor internal variable");
				printOption(stopVarMonitor, "Stop monitoring internal variable");
				printOption(pwm, "Set PWM output");
                printOption(setAIAdapter, "Set AI value adapter");
                printOption(setVarMonitorAdapter, "Set internal variable value adapter");
				printOption(exit, "Exit");
			}
			writeln();
			write("Select an option: ");

			int option = -1;
			string input = readln().chomp();
			formattedRead(input, " %s", &option);

			void printCommunicationRequired()
			{
				writeln("An established communication is required for this option.");
			}

			switch(option) with (Options)
			{
				case start:
					if(!puppeteer.isCommunicationEstablished)
					{
						writeln("Establishing communication with puppet...");
						if(puppeteer.startCommunication())
						{
							writeln("Communication established.");
						}
						else
							writeln("Could not establish communication with puppet.");
					}
					else
						writeln("Communication is already established.");

					break;

				case stop:
					if(puppeteer.isCommunicationEstablished)
					{
						puppeteer.endCommunication();
						writeln("Communication ended.");
					}
					else
						writeln("Communication has not been established yet.");
					break;

				case startPinMonitor:
					if(puppeteer.isCommunicationEstablished)
						addPinMonitor();
					else
						printCommunicationRequired();
					break;

				case stopPinMonitor:
					if(puppeteer.isCommunicationEstablished)
						removePinMonitor();
					else
						printCommunicationRequired();
					break;

				case startVarMonitor:
					if(puppeteer.isCommunicationEstablished)
						addVarMonitor();
					else
						printCommunicationRequired();
					break;

				case stopVarMonitor:
					if(puppeteer.isCommunicationEstablished)
						removeVarMonitor();
					else
						printCommunicationRequired();
					break;

				case pwm:
					if(puppeteer.isCommunicationEstablished)
						setPWM();
					else
						printCommunicationRequired();
					break;

                case setAIAdapter:
                    setAIValueAdapter();
                    break;

                case setVarMonitorAdapter:
                    setVarMonitorValueAdapter();
                    break;

				case exit:
					if(puppeteer.isCommunicationEstablished)
					{
						writeln("Finishing communication with puppet...");
						puppeteer.endCommunication();
					}
					loggerTid.send(MainMessage("END"));
					break menu;

				default:
					writeln("Please select a valid option.");
			}
		}
	}

	showMenu();
}

class PuppetListener
{
	Puppeteer!short puppeteer;

	this(Puppeteer!short puppeteer)
	{
		this.puppeteer = puppeteer;
	}

	void pinListenerMethod(ubyte pin, float value, long msecs) shared
	{
		locate(loggerTidName).send(MainMessage(to!string(msecs)~" => Pin "~to!string(pin)~" read "~to!string(value)));
	}

	void varListenerMethod(VarType)(ubyte varIndex, VarType value, long msecs) shared
	{
		locate(loggerTidName).send(MainMessage(to!string(msecs)~" => Var "~to!string(varIndex)~ " of type " ~ VarType.stringof ~ " read "~to!string(value)));
	}

	void addPinListener(ubyte pin)
	{
		puppeteer.addPinListener(pin, &pinListenerMethod);
	}

	void removePinListener(ubyte pin)
	{
		puppeteer.removePinListener(pin, &pinListenerMethod);
	}

	void addVarListener(VarType)(ubyte varIndex)
	{
		puppeteer.addVariableListener(varIndex, &varListenerMethod!VarType);
	}

	void removeVarListener(VarType)(ubyte varIndex)
	{
		puppeteer.removeVariableListener(varIndex, &varListenerMethod!VarType);
	}
}

struct MainMessage
{
	private string message;

	this(string message)
	{
		this.message = message;
	}
}
